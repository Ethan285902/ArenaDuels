//
//  RemotePlayer.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 24/11/2026.
//

import SceneKit
import AppKit

/// One position update from a remote player, stamped with the time THEIR Mac sent it.
struct Snapshot {
    let ts: Double
    let pos: SIMD3<Float>
    let yaw: Float
    let crouch: Bool
    let cut: Bool          // the player teleported (respawn), so don't blend from the previous position
}

/// Another player in the match (or the practice dummy): their model, name tag, and a jitter buffer
/// that plays their movement back smoothly even when the Wi-Fi is bumpy.
final class RemotePlayer {
    static let enemyColor = NSColor(red: 1.0, green: 0.36, blue: 0.4, alpha: 1)
    static let allyColor = NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1)

    let id: Int
    let humanoid: Humanoid
    var name: String
    var team: Int
    var isDummy = false
    var teammate = false
    var alive = true
    var hasData = false
    var scoping = false              // aiming through a sniper scope
    var pitch: Float = 0
    var aimedAtMe = false            // set by the game: is their scope pointing at me?
    private var glintNode: SCNNode?

    // Playback buffer, driven by the sender's clock
    var snaps: [Snapshot] = []
    var playhead: Double?
    var latestTs: Double = 0
    var delay: Double = 0.12             // how far behind the newest data we play (adapts to Wi-Fi jitter)
    var jitterPeak: Double = 0
    var lastTransit: Double?
    var lastSeq: UInt32 = 0
    var packetCount = 0

    // What is drawn
    var shownPos = SIMD3<Float>(0, 0.9, 0)       // body centre
    var shownYaw: Float = 0
    private var shownInit = false
    private var scale: Float = 1
    private var walkPhase: Float = 0
    private var tagNode: SCNNode?
    private var configured = false

    init(id: Int, name: String, team: Int) {
        self.id = id
        self.name = name
        self.team = team
        humanoid = Humanoid(color: RemotePlayer.enemyColor, tag: "p\(id)")
        humanoid.root.isHidden = true
    }

    /// Set the name, team and whether this player is on your team (blue with a name tag) or an enemy (red).
    func configure(name newName: String, team newTeam: Int, teammate mate: Bool) {
        let nameChanged = newName != name
        name = newName
        team = newTeam
        if !configured || mate != teammate {
            humanoid.setColor(mate ? RemotePlayer.allyColor : RemotePlayer.enemyColor)
        }
        teammate = mate
        configured = true
        if mate {
            if tagNode == nil || nameChanged { makeTag() }
        } else {
            tagNode?.removeFromParentNode()
            tagNode = nil
        }
    }

    private func makeTag() {
        tagNode?.removeFromParentNode()
        let text = SCNText(string: name, extrusionDepth: 0)
        text.font = NSFont.systemFont(ofSize: 0.3, weight: .bold)
        text.flatness = 0.05
        let m = SCNMaterial()
        m.diffuse.contents = NSColor.white
        m.emission.contents = NSColor.white
        m.lightingModel = .constant
        m.readsFromDepthBuffer = false               // visible through walls, like a team marker
        text.materials = [m]
        let node = SCNNode(geometry: text)
        let (lo, hi) = text.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, lo.y, 0)
        node.position = SCNVector3(0, 1.15, 0)
        node.renderingOrder = 100
        node.categoryBitMask = 2                     // bullets pass through the tag
        node.castsShadow = false
        let bb = SCNBillboardConstraint()
        bb.freeAxes = .Y
        node.constraints = [bb]
        humanoid.root.addChildNode(node)
        tagNode = node
    }

    // MARK: Sniper glint

    /// A soft star-shaped flare.
    static let glintImage = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { _ in
        let c = NSPoint(x: 64, y: 64)
        NSGradient(colors: [NSColor(white: 1, alpha: 1), NSColor(white: 1, alpha: 0)])?
            .draw(fromCenter: c, radius: 0, toCenter: c, radius: 60, options: [])
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 4, y: 62, width: 120, height: 4)).fill()
        NSBezierPath(rect: NSRect(x: 62, y: 4, width: 4, height: 120)).fill()
        return true
    }

    private func makeGlint() {
        let plane = SCNPlane(width: 0.9, height: 0.9)
        let m = SCNMaterial()
        m.diffuse.contents = RemotePlayer.glintImage
        m.lightingModel = .constant
        m.blendMode = .add
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0.35, 0.36, -0.8)            // at the front of the sniper's scope
        node.constraints = [SCNBillboardConstraint()]
        node.categoryBitMask = 2                                 // bullets pass through it
        node.castsShadow = false
        humanoid.root.addChildNode(node)
        glintNode = node
    }

    /// Enemy snipers sparkle while scoped. The sparkle flashes fast and bright if the scope is pointing at you.
    func updateGlint(now: Double) {
        let on = scoping && alive && hasData && !teammate && !isDummy
        guard on else { glintNode?.isHidden = true; return }
        if glintNode == nil { makeGlint() }
        guard let node = glintNode else { return }
        node.isHidden = false
        if aimedAtMe {
            let pulse = CGFloat(0.5 + 0.5 * sin(now * 22))
            node.opacity = 0.35 + 0.65 * pulse
            let s = 0.9 + 0.9 * pulse
            node.scale = SCNVector3(s, s, s)
        } else {
            node.opacity = 0.35                                  // a dim steady glint: a sniper is scoping somewhere
            node.scale = SCNVector3(0.8, 0.8, 0.8)
        }
    }

    // MARK: Receiving
    func receive(_ s: PlayerState) {
        guard s.seq > lastSeq || lastSeq - s.seq > 100_000 else { return }   // drop late or repeated updates
        lastSeq = s.seq
        packetCount += 1
        alive = s.alive
        scoping = s.scoping
        pitch = s.pitch
        hasData = true

        // Measure how bumpy the connection is, and keep a buffer big enough to hide it
        let transit = ProcessInfo.processInfo.systemUptime - s.ts
        if let lt = lastTransit {
            jitterPeak = max(abs(transit - lt), jitterPeak * 0.992)
            let desired = min(0.4, max(0.08, 0.07 + 1.3 * jitterPeak))
            delay += (desired - delay) * (desired > delay ? 0.3 : 0.01)   // grow fast, shrink slowly
        }
        lastTransit = transit

        let pos = SIMD3<Float>(s.x, s.y, s.z)
        var cut = false
        if let prev = snaps.last {
            let dx = pos.x - prev.pos.x, dz = pos.z - prev.pos.z
            cut = (dx * dx + dz * dz).squareRoot() > 5       // a jump this big is a respawn, not a run
        }
        snaps.append(Snapshot(ts: s.ts, pos: pos, yaw: s.yaw, crouch: s.crouch, cut: cut))
        if snaps.count > 120 { snaps.removeFirst(snaps.count - 120) }
        latestTs = s.ts
        if playhead == nil { playhead = s.ts - delay }
    }

    /// Where the player was at `time` (in THEIR clock), blended between the two updates around it.
    private func sample(at time: Double) -> (pos: SIMD3<Float>, yaw: Float, crouch: Bool, vel: SIMD3<Float>)? {
        guard let first = snaps.first, let last = snaps.last else { return nil }
        let zero = SIMD3<Float>(0, 0, 0)
        if snaps.count == 1 || time <= first.ts { return (first.pos, first.yaw, first.crouch, zero) }

        if time >= last.ts {
            // Ran out of updates: keep going in the same direction for a moment
            let prev = snaps[snaps.count - 2]
            let span = Float(last.ts - prev.ts)
            let v = (span > 0.001 && !last.cut) ? (last.pos - prev.pos) / span : zero
            let ahead = Float(min(time - last.ts, 0.25))
            return (last.pos + v * ahead * 0.7, last.yaw, last.crouch, v)
        }

        var i = snaps.count - 1
        while i > 1 && snaps[i - 1].ts > time { i -= 1 }
        let a = snaps[i - 1], b = snaps[i]
        if b.cut { return (a.pos, a.yaw, a.crouch, zero) }      // wait for the teleport
        let span = Float(b.ts - a.ts)
        let f = span > 0.0001 ? Float(time - a.ts) / span : 1
        var dy = b.yaw - a.yaw
        while dy > Float.pi { dy -= 2 * Float.pi }
        while dy < -Float.pi { dy += 2 * Float.pi }
        let v = span > 0.0001 ? (b.pos - a.pos) / span : zero
        return (a.pos + (b.pos - a.pos) * f, a.yaw + dy * f, b.crouch, v)
    }

    // MARK: Drawing (called every frame)
    func step(dt: Float) {
        var vel = SIMD3<Float>(0, 0, 0)
        var crouch = false
        if var ph = playhead {
            // Advance the playback clock. It speeds up or slows down slightly to stay `delay` behind the newest data.
            let err = (latestTs - delay) - ph
            if abs(err) > 0.6 {
                ph = latestTs - delay
            } else {
                ph += Double(dt) * (1 + max(-0.15, min(0.15, err * 0.6)))
            }
            ph = min(ph, latestTs + 0.25)
            playhead = ph

            if let s = sample(at: ph) {
                let diff = s.pos - shownPos
                let dist = (diff.x * diff.x + diff.z * diff.z).squareRoot()
                if dist > 3 || !shownInit {
                    shownPos = s.pos                         // first update, or a teleport (respawn)
                    shownInit = true
                } else {
                    shownPos += diff * min(1, dt * 30)       // very light smoothing
                }
                var dy = s.yaw - shownYaw
                while dy > Float.pi { dy -= 2 * Float.pi }
                while dy < -Float.pi { dy += 2 * Float.pi }
                shownYaw += dy * min(1, dt * 30)
                vel = s.vel
                crouch = s.crouch
            }
        }
        apply(vel: vel, crouch: crouch, dt: dt)
    }

    /// Put the model where `shownPos` says, and animate the limbs.
    func apply(vel: SIMD3<Float>, crouch: Bool, dt: Float) {
        scale += ((crouch ? 0.65 : 1) - scale) * min(1, dt * 10)
        humanoid.root.isHidden = !(hasData && alive)
        humanoid.root.scale = SCNVector3(1, CGFloat(scale), 1)
        humanoid.root.position = SCNVector3(shownPos.x, shownPos.y - 0.9 + 0.9 * scale, shownPos.z)
        humanoid.root.eulerAngles.y = CGFloat(shownYaw)
        let speed = (vel.x * vel.x + vel.z * vel.z).squareRoot()
        walkPhase += speed * dt * 2.2
        humanoid.animate(speed: speed, phase: walkPhase)
        updateGlint(now: ProcessInfo.processInfo.systemUptime)
    }
}
