//
//  Bots.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 26/11/2026.
//

import SceneKit
import Foundation

private func len2(_ v: SIMD2<Float>) -> Float { (v.x * v.x + v.y * v.y).squareRoot() }
private func len3(_ v: SIMD3<Float>) -> Float { (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot() }

/// Anyone who can be shot at: the host's player, other players, or bots.
struct Combatant {
    let id: Int
    let pos: SIMD3<Float>      // body centre
    let alive: Bool
}

/// A computer-controlled player. Only the HOST runs bots. Everyone else just sees them as ordinary players.
final class BotBrain {
    unowned let world: GameWorld
    let id: Int
    var name: String
    var pos = SIMD2<Float>(0, 0)          // x, z
    var yaw: Float = 0
    var pitch: Float = 0
    var health = 100
    var alive = false
    var weaponIndex = 0
    var scoping = false
    var invulnerableUntil: TimeInterval = 0

    private var seq: UInt32 = 0
    private var vel = SIMD2<Float>(0, 0)
    private var waypoint = SIMD2<Float>(0, 0)
    private var hasWaypoint = false
    private var targetID: Int?
    private var retarget: Float = 0
    private var reaction: Float = 0
    private var scopeTime: Float = 0
    private var nextShot: TimeInterval = 0
    private var strafe: Float = 1
    private var strafeTimer: Float = 0
    private var stuckTimer: Float = 0
    private var lastPos = SIMD2<Float>(0, 0)
    private var respawnTimer: Float = 0

    init(world: GameWorld, id: Int, name: String) {
        self.world = world
        self.id = id
        self.name = name
    }

    // Difficulty: 0 easy, 1 normal, 2 hard
    private var level: Int { min(2, max(0, world.net.botDifficulty)) }
    private var accuracy: Float { [0.22, 0.38, 0.55][level] }
    private var reactionTime: Float { [0.9, 0.55, 0.3][level] }
    private var fireScale: Double { [1.7, 1.25, 1.0][level] }
    private var turnSpeed: Float { [4, 7, 12][level] }
    private var vision: Float { [40, 55, 75][level] }

    func respawn(initial: Bool) {
        let sp = initial ? world.initialSpawn(for: id) : world.bestSpawn(for: id)
        let now = ProcessInfo.processInfo.systemUptime
        pos = SIMD2<Float>(sp.x, sp.z)
        yaw = sp.yaw
        pitch = 0
        health = 100
        alive = true
        scoping = false
        targetID = nil
        hasWaypoint = false
        vel = SIMD2<Float>(0, 0)
        scopeTime = 0
        weaponIndex = pickWeapon()
        invulnerableUntil = now + (initial ? 0 : 1.5)
        nextShot = now + 1.0
    }

    private func pickWeapon() -> Int {
        let r = Float.random(in: 0...1)
        if world.arenaHalf >= 26 && r < 0.25 { return 2 }      // snipers like big maps
        if r < 0.40 { return 0 }
        if r < 0.50 { return 1 }
        if r < 0.62 { return 7 }
        if r < 0.70 { return 8 }
        if r < 0.78 { return 9 }
        if r < 0.86 { return 3 }
        if r < 0.92 { return 4 }
        if r < 0.96 { return 10 }
        return 11
    }

    func takeDamage(_ amount: Int, from shooter: Int) {
        guard alive, world.phase == .playing,
              ProcessInfo.processInfo.systemUptime >= invulnerableUntil else { return }
        health -= amount
        retarget = 0                                           // look around quickly after being shot
        if health <= 0 {
            health = 0
            alive = false
            scoping = false
            respawnTimer = 3
            world.hostHandleDeath(victim: id, killer: shooter)
        }
    }

    func makeState(now: TimeInterval) -> PlayerState {
        seq &+= 1
        return PlayerState(id: id, x: pos.x, y: 0.9, z: pos.y, yaw: yaw, crouch: false, alive: alive,
                           seq: seq, ts: now, pitch: pitch, scoping: scoping && alive)
    }

    // MARK: Thinking

    private func preferredRange(_ w: Weapon) -> (Float, Float) {
        if w.scope { return (25, 45) }
        if w.pellets > 1 { return (3, 8) }
        if w.fireDelay > 0.3 { return (8, 16) }
        return (10, 22)
    }

    func update(dt: Float, now: TimeInterval, others: [Combatant]) {
        guard world.phase == .playing else { return }       // stand still during the countdown and between rounds
        if !alive {
            if world.mode.respawns {
                respawnTimer -= dt
                if respawnTimer <= 0 { respawn(initial: false) }
            }
            return
        }
        let w = Weapon.all[weaponIndex]
        let eye = SIMD3<Float>(pos.x, 1.6, pos.y)

        // Look for the nearest enemy it can see, a few times a second
        retarget -= dt
        if retarget <= 0 {
            retarget = 0.3
            var best: Combatant?
            var bestD = vision
            for c in others where c.alive && c.id != id && world.areEnemies(id, c.id) {
                let d = len3(c.pos - eye)
                if d < bestD && !world.lineBlocked(eye, c.pos) { best = c; bestD = d }
            }
            if let b = best {
                if targetID != b.id { targetID = b.id; reaction = reactionTime; scopeTime = 0 }
            } else {
                targetID = nil
            }
        }
        let target = targetID.flatMap { tid in others.first(where: { $0.id == tid && $0.alive }) }

        var move = SIMD2<Float>(0, 0)
        var speed: Float = 4.8 * w.moveMul

        if let t = target {
            let toT = SIMD2<Float>(t.pos.x - pos.x, t.pos.z - pos.y)
            let dist = len2(toT)
            let dir = dist > 0.001 ? toT / dist : SIMD2<Float>(0, 1)

            // Turn to face the target
            let desiredYaw = atan2(-dir.x, -dir.y)
            var dy = desiredYaw - yaw
            while dy > Float.pi { dy -= 2 * Float.pi }
            while dy < -Float.pi { dy += 2 * Float.pi }
            yaw += dy * min(1, dt * turnSpeed)
            let desiredPitch = atan2(t.pos.y - 1.6, max(dist, 0.5))
            pitch += (desiredPitch - pitch) * min(1, dt * turnSpeed)

            // Keep a good fighting distance and strafe from side to side
            let (lo, hi) = preferredRange(w)
            var forward: Float = 0
            if dist > hi { forward = 1 } else if dist < lo { forward = -1 }
            strafeTimer -= dt
            if strafeTimer <= 0 {
                strafeTimer = Float.random(in: 0.7...1.6)
                strafe = Bool.random() ? 1 : -1
            }
            let side = SIMD2<Float>(-dir.y, dir.x)
            move = dir * forward + side * strafe * (w.scope ? 0 : 0.7)
            speed *= 0.85

            // Shoot once it has reacted and is facing the target (snipers aim through the scope first)
            reaction -= dt
            if w.scope {
                scoping = true
                scopeTime += dt
            }
            if reaction <= 0 && abs(dy) < 0.12 && dist < w.range && now >= nextShot
                && (!w.scope || scopeTime > 0.9) {
                shoot(at: t, dist: dist, now: now)
            }
        } else {
            scoping = false
            // Wander: walk to a spot, sometimes towards an enemy so fights actually happen
            if !hasWaypoint || len2(waypoint - pos) < 2 { pickWaypoint(others: others) }
            let toW = waypoint - pos
            let d = len2(toW)
            if d > 0.01 {
                let dir = toW / d
                move = dir
                let desiredYaw = atan2(-dir.x, -dir.y)
                var dy = desiredYaw - yaw
                while dy > Float.pi { dy -= 2 * Float.pi }
                while dy < -Float.pi { dy += 2 * Float.pi }
                yaw += dy * min(1, dt * turnSpeed)
                pitch -= pitch * min(1, dt * 4)
            }
        }

        // Move, and slide along walls
        let ml = len2(move)
        if ml > 1 { move /= ml }
        vel += (move * speed - vel) * min(1, dt * 10)
        pos += vel * dt
        let lim = world.arenaHalf - 1
        pos.x = max(-lim, min(lim, pos.x))
        pos.y = max(-lim, min(lim, pos.y))
        world.pushOutOfSolids(&pos, feetY: 0, radius: 0.4)

        // Stuck behind something? Pick somewhere else to go.
        stuckTimer += dt
        if stuckTimer > 0.6 {
            if len2(pos - lastPos) < 0.4 && ml > 0.1 {
                hasWaypoint = false
                strafe = -strafe
                strafeTimer = 0
            }
            lastPos = pos
            stuckTimer = 0
        }
    }

    private func pickWaypoint(others: [Combatant]) {
        let lim = world.arenaHalf - 2
        let enemies = others.filter { $0.alive && $0.id != id && world.areEnemies(id, $0.id) }
        if let e = enemies.randomElement(), Bool.random() {
            waypoint = SIMD2<Float>(e.pos.x + Float.random(in: -3...3), e.pos.z + Float.random(in: -3...3))
        } else {
            waypoint = SIMD2<Float>(Float.random(in: -lim...lim), Float.random(in: -lim...lim))
        }
        waypoint.x = max(-lim, min(lim, waypoint.x))
        waypoint.y = max(-lim, min(lim, waypoint.y))
        hasWaypoint = true
    }

    /// A shot is worked out with dice rather than a real bullet: the further away, the lower the chance.
    private func shoot(at t: Combatant, dist: Float, now: TimeInterval) {
        let w = Weapon.all[weaponIndex]
        nextShot = now + w.fireDelay * fireScale + Double.random(in: 0...0.15)
        world.botFired(id: id, weapon: weaponIndex)
        var acc = accuracy
        if w.scope { acc = min(0.9, acc * 1.7) }
        let rangeFactor = max(0.08, 1 - dist / max(12, w.range * 0.75))
        var total: Float = 0
        for _ in 0..<w.pellets {
            guard Float.random(in: 0...1) < acc * rangeFactor else { continue }
            let head = Float.random(in: 0...1) < 0.12
            let f = max(0, min(1, (dist - w.falloffStart) / max(0.01, w.falloffEnd - w.falloffStart)))
            total += Float(w.damage) * (head ? w.headMul : 1) * (1 - (1 - w.minDamageMul) * f)
        }
        if total > 0 { world.botDealDamage(from: self, to: t.id, amount: Int(total.rounded())) }
        if w.scope { scopeTime = 0 }                          // aim again before the next shot
    }
}

// MARK: - What the world provides to bots (and the sniper warning)

extension GameWorld {
    func areEnemies(_ a: Int, _ b: Int) -> Bool {
        a != b && (!net.snap.mode.usesTeams || teamOf(a) != teamOf(b))
    }

    /// Everyone who is in the fight, with where they are.
    func combatants() -> [Combatant] {
        var out: [Combatant] = []
        out.append(Combatant(id: net.myID,
                             pos: SIMD3<Float>(Float(playerNode.position.x), feetY + 0.9, Float(playerNode.position.z)),
                             alive: alive))
        for r in remotes.values where !r.isDummy && bots[r.id] == nil {
            out.append(Combatant(id: r.id, pos: r.shownPos, alive: r.alive && r.hasData))
        }
        for b in bots.values {
            out.append(Combatant(id: b.id, pos: SIMD3<Float>(b.pos.x, 0.9, b.pos.y), alive: b.alive))
        }
        return out
    }

    /// Is there a block between these two points? (a line against every block)
    func lineBlocked(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        let d = b - a
        for o in obstacles {
            let lo = SIMD3<Float>(o.x - o.hw, o.base, o.z - o.hl)
            let hi = SIMD3<Float>(o.x + o.hw, o.top, o.z + o.hl)
            var tmin: Float = 0
            var tmax: Float = 1
            var hit = true
            for axis in 0..<3 {
                if abs(d[axis]) < 0.000001 {
                    if a[axis] < lo[axis] || a[axis] > hi[axis] { hit = false; break }
                } else {
                    var t1 = (lo[axis] - a[axis]) / d[axis]
                    var t2 = (hi[axis] - a[axis]) / d[axis]
                    if t1 > t2 { swap(&t1, &t2) }
                    tmin = max(tmin, t1)
                    tmax = min(tmax, t2)
                    if tmin > tmax { hit = false; break }
                }
            }
            if hit { return true }
        }
        return false
    }

    /// Slide a circle out of any block it is inside (used by bots).
    func pushOutOfSolids(_ p: inout SIMD2<Float>, feetY: Float, radius: Float) {
        for o in obstacles where o.top > feetY + stepUp && o.base < feetY + 1.8 {
            let cx = max(o.x - o.hw, min(o.x + o.hw, p.x))
            let cz = max(o.z - o.hl, min(o.z + o.hl, p.y))
            let dx = p.x - cx, dz = p.y - cz
            let d = (dx * dx + dz * dz).squareRoot()
            if d < radius {
                if d > 0.0001 {
                    p.x = cx + dx / d * radius
                    p.y = cz + dz / d * radius
                } else {
                    let left = p.x - (o.x - o.hw), rightSide = (o.x + o.hw) - p.x
                    let back = p.y - (o.z - o.hl), front = (o.z + o.hl) - p.y
                    let m = min(left, rightSide, back, front)
                    if m == left { p.x = o.x - o.hw - radius }
                    else if m == rightSide { p.x = o.x + o.hw + radius }
                    else if m == back { p.y = o.z - o.hl - radius }
                    else { p.y = o.z + o.hl + radius }
                }
            }
        }
    }

    /// A good place to respawn: one of the spots farthest from the enemies of `id`.
    func bestSpawn(for id: Int) -> (x: Float, z: Float, yaw: Float) {
        let pts = spawnCandidates()
        guard !pts.isEmpty else { return initialSpawn(for: id) }
        let foes = combatants().filter { $0.alive && areEnemies(id, $0.id) }.map { SIMD2<Float>($0.pos.x, $0.pos.z) }
        var scored: [(Float, SIMD2<Float>)] = pts.map { p in
            let d = foes.map { len2(SIMD2<Float>($0.x - p.x, $0.y - p.y)) }.min() ?? 99
            return (d, p)
        }
        scored.sort { $0.0 > $1.0 }
        let pick = scored[Int.random(in: 0..<min(3, scored.count))].1
        return (pick.x, pick.y, atan2(pick.x, pick.y))
    }

    // MARK: Running the bots (host only)

    func syncBots() {
        guard net.isHost, !net.practice else { return }
        let infos = net.snap.players.filter { $0.isBot }
        let ids = Set(infos.map { $0.id })
        for id in Array(bots.keys) where !ids.contains(id) { bots[id] = nil }
        for p in infos {
            if let b = bots[p.id] { b.name = p.name }
            else { bots[p.id] = BotBrain(world: self, id: p.id, name: p.name) }
        }
    }

    func updateBots(dt: Float, now: TimeInterval) {
        guard net.isHost, !net.practice, !bots.isEmpty else { return }
        let others = combatants()
        for b in Array(bots.values) { b.update(dt: dt, now: now, others: others) }
    }

    /// Send each bot's position to everyone, and show it on the host's own screen too.
    func sendBotStates() {
        guard net.isHost, !bots.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for b in bots.values {
            let st = b.makeState(now: now)
            net.send(.state(st), reliable: false)
            remotes[b.id]?.receive(st)
        }
    }

    func botFired(id: Int, weapon: Int) {
        net.send(.shot(id: id, weapon: weapon), reliable: false)
        playRemoteShot(id: id, weapon: weapon)
    }

    func botDealDamage(from bot: BotBrain, to id: Int, amount: Int) {
        if id == net.myID {
            applyHitToMe(shooter: bot.id, dmg: amount)
        } else if let b = bots[id] {
            b.takeDamage(amount, from: bot.id)
        } else {
            net.send(.hit(shooter: bot.id, target: id, damage: amount), reliable: true)
        }
    }

    /// Someone shot me. Apply the damage (unless I'm protected, dead, or it was a teammate).
    func applyHitToMe(shooter: Int, dmg: Int) {
        guard phase == .playing, alive, ProcessInfo.processInfo.systemUptime >= invulnerableUntil else { return }
        if net.snap.mode.usesTeams && teamOf(shooter) == myTeam { return }       // no friendly fire
        health -= dmg
        flashDamage()
        if health <= 0 { iDied(killer: shooter) }
    }

    // MARK: Sniper warning

    /// Works out whether an enemy sniper is scoping at me, and which way to look.
    func updateSniperThreat() {
        var threat: Double?
        let now = ProcessInfo.processInfo.systemUptime
        if alive && phase == .playing {
            let me = SIMD3<Float>(Float(playerNode.position.x), feetY + 1.0, Float(playerNode.position.z))
            let fwd = SIMD2<Float>(-sin(yaw), -cos(yaw))
            let right = SIMD2<Float>(cos(yaw), -sin(yaw))
            for r in remotes.values where !r.isDummy {
                var aimed = false
                if r.scoping && r.alive && isEnemy(r.id) {
                    let eye = r.shownPos + SIMD3<Float>(0, 0.7, 0)
                    let aim = SIMD3<Float>(-sin(r.shownYaw) * cos(r.pitch), sin(r.pitch), -cos(r.shownYaw) * cos(r.pitch))
                    let d = me - eye
                    let dist = len3(d)
                    if dist > 1 {
                        let cosA = (aim.x * d.x + aim.y * d.y + aim.z * d.z) / dist
                        let tol = cos(atan2(Float(0.9), dist) + 0.05)       // about a body's width, plus a little
                        aimed = cosA > tol && !lineBlocked(eye, me)
                    }
                    if aimed {
                        let toThem = SIMD2<Float>(-d.x, -d.z)
                        threat = Double(atan2(toThem.x * right.x + toThem.y * right.y,
                                              toThem.x * fwd.x + toThem.y * fwd.y))
                    }
                }
                r.aimedAtMe = aimed
            }
        } else {
            for r in remotes.values { r.aimedAtMe = false }
        }
        if threat != nil && now - lastWarnBeep > 0.7 {
            lastWarnBeep = now
            playSound("Morse", volume: 0.6)
        }
        if (threat == nil) != (sniperThreat == nil) || abs((threat ?? 0) - (sniperThreat ?? 0)) > 0.05 {
            sniperThreat = threat
        }
    }

    // MARK: Trophies

    /// I just got a kill. Credit the right trophies, using what I remember about my last hit on that player.
    func registerMyKill(victim: Int) {
        guard !net.practice else { return }
        let t = Trophies.shared
        t.add("kills")
        if net.snap.players.first(where: { $0.id == victim })?.isBot == true { t.add("botKills") }
        lifeKills += 1
        if lifeKills == 3 { t.add("tripleKills") }
        if lifeKills == 5 { t.add("fiveKills") }
        if victim == lastKillerOfMe { t.add("revenge"); lastKillerOfMe = -1 }
        if let i = lastHit[victim], ProcessInfo.processInfo.systemUptime - i.time < 5 {
            if i.head { t.add("headshotKills") }
            if Weapon.all[i.weapon].melee { t.add("meleeKills") }
            if i.weapon == 1 { t.add("shotgunKills") }
            if i.weapon == 2 {
                t.add("sniperKills")
                if i.dist >= 50 { t.add("longShots") }
            }
            if i.sliding { t.add("slideKills") }
            if i.airborne { t.add("airKills") }
            if i.high { t.add("highGroundKills") }
        }
    }

    func showToast(_ t: Toast) {
        if toast == nil { presentToast(t) } else { toastQueue.append(t) }
    }

    func presentToast(_ t: Toast) {
        toast = t
        playSound("Glass")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self else { return }
            self.toast = nil
            if !self.toastQueue.isEmpty { self.presentToast(self.toastQueue.removeFirst()) }
        }
    }
}
