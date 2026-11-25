//
//  GameWorld.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 23/11/2026.
//

import Combine
import SceneKit
import SwiftUI

struct FeedItem: Identifiable {
    let id = UUID()
    let text: String
    let good: Bool
}

/// A solid block you can bump into, or climb onto if it is low enough.
struct Solid {
    let x: Float
    let z: Float
    let hw: Float          // half width (x)
    let hl: Float          // half length (z)
    let base: Float        // height of the bottom (0 = on the floor; higher = a bridge you can walk under)
    let top: Float         // height of the top surface
}

/// Pre-loaded sound objects so firing never has to load a file in the middle of a frame.
final class SoundBank {
    static let shared = SoundBank()
    private var pools: [String: [NSSound]] = [:]
    private var next: [String: Int] = [:]

    func warm(_ name: String) {
        guard pools[name] == nil else { return }
        var arr: [NSSound] = []
        if let base = NSSound(named: NSSound.Name(name)) {
            for _ in 0..<4 {
                if let c = base.copy() as? NSSound { arr.append(c) }
            }
        }
        pools[name] = arr
    }

    func play(_ name: String, volume: Float) {
        warm(name)
        guard let pool = pools[name], !pool.isEmpty else { return }
        let i = (next[name] ?? 0) % pool.count
        next[name] = i + 1
        let s = pool[i]
        s.stop()
        s.volume = volume
        s.play()
    }
}

final class GameWorld: NSObject, ObservableObject, SCNSceneRendererDelegate {
    // MARK: Scene objects
    let scene = SCNScene()
    let playerNode = SCNNode()      // position + left/right turn
    let cameraNode = SCNNode()      // up/down look
    let gunNode = SCNNode()         // first-person weapon
    let flashNode = SCNNode()       // first-person muzzle flash
    let arenaNode = SCNNode()       // floor and walls (rebuilt when the map size changes)
    let mapNode = SCNNode()         // swappable cover boxes
    let remoteRoot = SCNNode()      // every other player
    let sunNode = SCNNode()
    let accentMaterial = SCNMaterial()   // wall trim and spawn pads, recoloured per map
    let net: GameNetwork
    var cancellables = Set<AnyCancellable>()

    // MARK: Other players
    let dummyID = 100                              // the practice dummy
    var remotes: [Int: RemotePlayer] = [:]

    // MARK: Movement state (only ever touched on the main thread)
    var keys = Set<UInt16>()
    var binds = Keybinds.load()
    var yaw: Float = 0
    var pitch: Float = 0
    var lastTime: TimeInterval = 0
    var vel = SIMD2<Float>(0, 0)
    var vy: Float = 0
    var feetY: Float = 0              // height of the player's feet above the floor
    var groundY: Float = 0            // height of whatever the player is standing on (floor or a box top)
    let stepUp: Float = 0.5           // you walk up anything this much higher than your feet
    var eyeY: Float = 1.6
    var roll: Float = 0
    var bobPhase: Float = 0
    var recoil: Float = 0                         // gun model kick-back
    var recoilPitch: Float = 0                    // camera recoil, recovers over time
    var recoilYaw: Float = 0
    var swayYaw: Float = 0                        // the gun lags behind when you turn
    var swayPitch: Float = 0
    var bloom: Float = 0                          // spread added by sustained fire (degrees)
    var shotIndex = 0
    var lastShotTime: TimeInterval = 0
    var nextFire: TimeInterval = 0
    var reloadStart: TimeInterval = 0
    var reloadDuration: TimeInterval = 1
    var equipStart: TimeInterval = 0
    var equipDuration: TimeInterval = 0.4
    var adsAmount: Float = 0                      // 0 = hip, 1 = fully aimed
    var sprintAmount: Float = 0
    var sliding = false
    var slideSpeed: Float = 0
    var slideDir = SIMD2<Float>(0, 0)
    var slideCooldown: Float = 0
    var wasSlideKey = false
    var crouching = false
    var arenaHalf: Float = 15
    var obstacles: [Solid] = []

    // MARK: Published HUD state
    @Published var health = 100
    @Published var alive = true
    @Published var respawnIn = 0
    @Published var roundWon = false
    @Published var hitMarker = false
    @Published var headshot = false
    @Published var damageFlash = 0.0
    @Published var paused = false
    @Published var mouseCaptured = false
    @Published var aiming = false
    @Published var showScoreboard = false
    @Published var crosshairGap = 6.0
    @Published var stats = ""
    @Published var feed: [FeedItem] = []
    @Published var mapName = ""
    @Published var loadout = Loadout.load()       // [primary, secondary, melee] as indices into Weapon.all
    @Published var weaponIndex = 0                // the weapon in hand, as an index into Weapon.all
    @Published var ammo = Weapon.all.map { $0.magSize }
    @Published var reloading = false
    @Published var sniperThreat: Double?          // direction of an enemy sniper aiming at me (nil = none)
    @Published var toast: Toast?                  // trophy banner
    @Published var trophyDelta: Int?              // trophy points won or lost, shown at the end of a match

    // MARK: Match state (the official copy lives in net.snap)
    var snap: MatchSnapshot { net.snap }
    var mode: GameMode { net.snap.mode }
    var phase: Phase { net.snap.phase }
    var myID: Int { net.myID }
    var myTeam: Int { teamOf(net.myID) }

    func teamOf(_ id: Int) -> Int { net.snap.players.first { $0.id == id }?.team ?? 0 }

    func isEnemy(_ id: Int) -> Bool {
        id != net.myID && (!net.snap.mode.usesTeams || teamOf(id) != myTeam)
    }

    var scoped: Bool { aiming && alive && Weapon.all[weaponIndex].scope }

    // HUD helpers
    var myKills: Int { net.snap.players.first { $0.id == net.myID }?.kills ?? 0 }
    var topKills: Int { net.snap.players.map { $0.kills }.max() ?? 0 }
    var allyScore: Int { net.snap.teamScore.indices.contains(myTeam) ? net.snap.teamScore[myTeam] : 0 }
    var enemyScore: Int { net.snap.teamScore.indices.contains(1 - myTeam) ? net.snap.teamScore[1 - myTeam] : 0 }

    var leftLabel: String { isDuel ? "YOU" : "ALLIES" }
    var rightLabel: String {
        isDuel ? (net.snap.players.first { $0.id != net.myID }?.name.uppercased() ?? "ENEMY") : "ENEMIES"
    }
    var isDuel: Bool { net.snap.mode == .elimination && net.snap.players.count == 2 }

    var timeText: String? {
        guard net.snap.mode.timeLimit > 0, !net.practice, net.snap.phase == .playing else { return nil }
        let t = max(0, net.snap.timeLeft)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    var alliesAlive: Int {
        (alive ? 1 : 0) + remotes.values.filter { !$0.isDummy && $0.teammate && $0.alive }.count
    }
    var enemiesAlive: Int {
        remotes.values.filter { !$0.isDummy && !$0.teammate && $0.alive }.count
    }

    var matchResultText: String {
        let w = net.snap.winner
        if w < 0 { return "DRAW" }
        if net.snap.mode.usesTeams { return w == myTeam ? "VICTORY" : "DEFEAT" }
        return w == net.myID ? "VICTORY" : "\(net.name(of: w).uppercased()) WINS"
    }

    // MARK: Game state
    var practiceHP = 100
    var practiceMoves = true
    var firing = false
    var reloadToken = 0
    var lastScrollSwitch: TimeInterval = 0
    var timers: [Timer] = []
    var monitor: Any?
    var resignObserver: NSObjectProtocol?
    var updatePending = false
    let pendingLock = NSLock()
    var frames = 0
    var lastStatTime: TimeInterval = 0
    var currentMap = 0
    var sendTick = 0
    var mySeq: UInt32 = 0
    var invulnerableUntil: TimeInterval = 0
    var respawnToken = 0

    // Bots (host only), trophies, and warnings
    var bots: [Int: BotBrain] = [:]
    var lastHit: [Int: HitInfo] = [:]
    var lifeKills = 0
    var lastKillerOfMe = -1
    var toastQueue: [Toast] = []
    var lastWarnBeep: TimeInterval = 0

    // Host only
    var roundToken = 0
    var aliveSet = Set<Int>()
    var matchTimer: Timer?
    var clockStarted = false

    // Used to notice changes in the match state
    var lastPhase: Phase = .waiting
    var lastCountdown = -1
    var lastTeamScore = [0, 0]

    // MARK: Init
    init(net: GameNetwork) {
        self.net = net
        super.init()
        currentMap = net.snap.map
        for name in ["Pop", "Blow", "Sosumi", "Purr", "Tink", "Ping", "Glass", "Funk", "Basso", "Hero", "Bottle", "Frog"] {
            SoundBank.shared.warm(name)
        }
        buildArena()
        if net.practice { addDummy() }
        respawn()
        installInput()
        net.onMessage = { [weak self] in self?.handle($0) }
        net.onPlayerLeft = { [weak self] id in self?.playerLeft(id) }
        net.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        lastStatTime = ProcessInfo.processInfo.systemUptime
        Trophies.shared.onUnlock = { [weak self] a in self?.showToast(Toast(title: a.title, detail: a.detail)) }
        handleMatch(net.snap)

        // Send our position 60 times per second (30 when there are many players)
        let sendTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.sendState() }
        RunLoop.main.add(sendTimer, forMode: .common)
        timers.append(sendTimer)

        // Hold the mouse for automatic weapons
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self, self.firing, Weapon.all[self.weaponIndex].auto else { return }
            self.fire()
        })

        // Size the crosshair from the real bullet spread
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let w = Weapon.all[self.weaponIndex]
            let zoom = 1 + (w.adsFov - 1) * self.adsAmount
            let fovDeg = max(10, Float(Prefs.fov) * zoom)
            let gap = min(80, Double(self.currentSpreadDeg() * 700 / fovDeg) + 2)
            if abs(gap - self.crosshairGap) > 0.5 { self.crosshairGap = gap }
            self.updateSniperThreat()
        })

        // Release the mouse if the player switches to another app
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.pause() }

        // The host starts the first round a moment after everyone has loaded
        if net.isHost {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.hostBeginRound()
            }
        }
    }

    deinit {
        timers.forEach { $0.invalidate() }
        Trophies.shared.onUnlock = nil
        matchTimer?.invalidate()
        if let m = monitor { NSEvent.removeMonitor(m) }
        if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
        if mouseCaptured {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
        }
    }

    // MARK: Other players
    func addDummy() {
        let d = RemotePlayer(id: dummyID, name: "Dummy", team: 1)
        d.isDummy = true
        d.hasData = true
        d.shownPos = SIMD3<Float>(-4, 0.9, 0)
        d.shownYaw = .pi / 2
        d.configure(name: "Dummy", team: 1, teammate: false)
        remoteRoot.addChildNode(d.humanoid.root)
        remotes[dummyID] = d
    }

    /// Make sure there is a model for every other player in the match, and none for players who left.
    func syncRemotes() {
        let ids = Set(net.snap.players.map { $0.id }).subtracting([net.myID])
        for id in Array(remotes.keys) where id != dummyID && !ids.contains(id) {
            remotes[id]?.humanoid.root.removeFromParentNode()
            remotes[id] = nil
        }
        for p in net.snap.players where p.id != net.myID {
            let mate = net.snap.mode.usesTeams && p.team == myTeam
            if let r = remotes[p.id] {
                r.configure(name: p.name, team: p.team, teammate: mate)
            } else {
                let r = RemotePlayer(id: p.id, name: p.name, team: p.team)
                r.configure(name: p.name, team: p.team, teammate: mate)
                remoteRoot.addChildNode(r.humanoid.root)
                remotes[p.id] = r
            }
        }
    }

    func playerLeft(_ id: Int) {
        aliveSet.remove(id)
        syncRemotes()
        guard net.isHost, !net.practice else { return }
        if net.snap.players.count < 2 {
            roundToken += 1
            net.returnToRoom()                      // everyone else left
        } else if phase == .playing && mode == .elimination {
            checkEliminationEnd()
        }
    }

    // MARK: Spawning
    func freeSpot(_ x: Float, _ z: Float) -> Bool {
        for o in obstacles where abs(x - o.x) < o.hw + 0.9 && abs(z - o.z) < o.hl + 0.9 { return false }
        return true
    }

    func spawnCandidates() -> [SIMD2<Float>] {
        let r = arenaHalf - 5
        var pts: [SIMD2<Float>] = []
        for k in 0..<16 {
            let a = Float(k) / 16 * 2 * Float.pi
            let p = SIMD2<Float>(cos(a) * r, sin(a) * r)
            if freeSpot(p.x, p.y) { pts.append(p) }
        }
        return pts
    }

    /// Where a player starts a round: teams on opposite sides, free-for-all spread around a ring.
    func initialSpawn(for id: Int) -> (x: Float, z: Float, yaw: Float) {
        let r = arenaHalf - 5
        if net.practice { return (-r, 0, -Float.pi / 2) }
        if net.snap.mode.usesTeams {
            let team = teamOf(id)
            let members = net.snap.players.filter { $0.team == team }.sorted { $0.id < $1.id }
            let idx = members.firstIndex(where: { $0.id == id }) ?? 0
            let n = members.count
            let x: Float = team == 0 ? -r : r
            let z = (Float(idx) - Float(n - 1) / 2) * 2.6
            return (x, z, team == 0 ? -Float.pi / 2 : Float.pi / 2)
        }
        let ids = net.snap.players.map { $0.id }.sorted()
        let idx = ids.firstIndex(of: id) ?? 0
        let pts = spawnCandidates()
        guard !pts.isEmpty else { return (-r, 0, -Float.pi / 2) }
        let p = pts[(idx * pts.count / max(1, ids.count)) % pts.count]
        return (p.x, p.y, atan2(p.x, p.y))
    }

    /// Where to respawn mid-match: one of the spots farthest from the enemies.
    func bestRespawn() -> (x: Float, z: Float, yaw: Float) {
        let pts = spawnCandidates()
        guard !pts.isEmpty else { return initialSpawn(for: net.myID) }
        let enemies = remotes.values
            .filter { !$0.isDummy && $0.alive && isEnemy($0.id) }
            .map { SIMD2<Float>($0.shownPos.x, $0.shownPos.z) }
        var scored: [(Float, SIMD2<Float>)] = pts.map { p in
            let d = enemies.map { e in ((e.x - p.x) * (e.x - p.x) + (e.y - p.y) * (e.y - p.y)).squareRoot() }.min() ?? 99
            return (d, p)
        }
        scored.sort { $0.0 > $1.0 }
        let pick = scored[Int.random(in: 0..<min(3, scored.count))].1
        return (pick.x, pick.y, atan2(pick.x, pick.y))
    }

    // MARK: World building
    func buildArena() {
        scene.rootNode.addChildNode(arenaNode)
        scene.rootNode.addChildNode(mapNode)
        scene.rootNode.addChildNode(remoteRoot)
        loadMap(currentMap)     // builds the floor, walls and cover for the current map

        // Sunlight with soft shadows, plus ambient fill
        sunNode.light = SCNLight()
        sunNode.light?.type = .directional
        sunNode.light?.intensity = 650
        sunNode.light?.shadowMode = .deferred
        sunNode.light?.shadowRadius = 6
        sunNode.light?.shadowColor = NSColor(white: 0, alpha: 0.28)
        sunNode.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        sunNode.light?.shadowSampleCount = 4
        sunNode.light?.maximumShadowDistance = 60
        sunNode.eulerAngles = SCNVector3(-CGFloat.pi / 3, CGFloat.pi / 5, 0)
        scene.rootNode.addChildNode(sunNode)
        applyGraphicsPrefs()

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 420
        scene.rootNode.addChildNode(ambient)

        // Camera rig: playerNode turns left/right, cameraNode looks up/down
        let cam = SCNCamera()
        cam.zNear = 0.05
        cam.zFar = 500
        cam.fieldOfView = CGFloat(Prefs.fov)
        cameraNode.camera = cam
        cameraNode.addChildNode(gunNode)
        playerNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(playerNode)
        buildGun()
    }

    func applyGraphicsPrefs() {
        sunNode.light?.castsShadow = Prefs.shadows
    }

    /// Light tiled floor, white walls with coloured trim, and a glowing pad at each spawn.
    func buildFloorAndWalls() {
        arenaNode.childNodes.forEach { $0.removeFromParentNode() }
        let size = CGFloat(arenaHalf * 2)

        let tile = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1).setFill()
            rect.fill()
            NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 128, height: 128).fill()
            NSRect(x: 128, y: 128, width: 128, height: 128).fill()
            NSColor(red: 0.76, green: 0.80, blue: 0.87, alpha: 1).setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
            return true
        }
        let floorMat = SCNMaterial()
        floorMat.diffuse.contents = tile
        floorMat.diffuse.wrapS = .repeat
        floorMat.diffuse.wrapT = .repeat
        floorMat.diffuse.contentsTransform = SCNMatrix4MakeScale(size / 2, size / 2, 1)   // 2 units per tile
        floorMat.diffuse.minificationFilter = .linear
        floorMat.diffuse.mipFilter = .linear
        floorMat.lightingModel = .lambert
        let plane = SCNPlane(width: size, height: size)
        plane.materials = [floorMat]
        let floorNode = SCNNode(geometry: plane)
        floorNode.eulerAngles.x = -CGFloat.pi / 2
        arenaNode.addChildNode(floorNode)

        // Spawn pads (colour follows the map)
        for x in [CGFloat(-(arenaHalf - 5)), CGFloat(arenaHalf - 5)] {
            let pad = SCNCylinder(radius: 1.3, height: 0.02)
            pad.materials = [accentMaterial]
            let n = SCNNode(geometry: pad)
            n.position = SCNVector3(x, 0.011, 0)
            n.castsShadow = false
            arenaNode.addChildNode(n)
        }

        // Outer walls with a trim strip at the bottom and the top
        let h = arenaHalf
        let wallColor = NSColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1)
        let walls: [(Float, Float, Float, Float)] = [(0, -h, h * 2, 1), (0, h, h * 2, 1), (-h, 0, 1, h * 2), (h, 0, 1, h * 2)]
        for (x, z, w, l) in walls {
            addBox(x: x, z: z, w: w, h: 4, l: l, color: wallColor, parent: arenaNode)
            for y in [Float(0.2), Float(3.8)] {
                let strip = SCNNode(geometry: SCNBox(width: CGFloat(w) + 0.06, height: 0.4,
                                                     length: CGFloat(l) + 0.06, chamferRadius: 0))
                strip.geometry?.materials = [accentMaterial]
                strip.position = SCNVector3(x, y, z)
                strip.castsShadow = false
                arenaNode.addChildNode(strip)
            }
        }
    }

    func addBox(x: Float, z: Float, w: Float, h: Float, l: Float, color: NSColor,
                solid: Bool = false, parent: SCNNode? = nil, chamfer: CGFloat = 0, base: Float = 0) {
        if solid { obstacles.append(Solid(x: x, z: z, hw: w / 2, hl: l / 2, base: base, top: h)) }
        let box = SCNNode(geometry: SCNBox(width: CGFloat(w), height: CGFloat(h - base), length: CGFloat(l), chamferRadius: chamfer))
        box.geometry?.firstMaterial?.diffuse.contents = color
        box.position = SCNVector3(x, base + (h - base) / 2, z)
        (parent ?? scene.rootNode).addChildNode(box)
    }

    func loadMap(_ i: Int) {
        let count = ArenaMap.all.count
        let index = ((i % count) + count) % count
        let m = ArenaMap.all[index]
        currentMap = index
        arenaHalf = m.half

        obstacles.removeAll()
        mapNode.childNodes.forEach { $0.removeFromParentNode() }
        accentMaterial.diffuse.contents = m.accent
        accentMaterial.emission.contents = m.accent.blended(withFraction: 0.6, of: .black) ?? m.accent
        buildFloorAndWalls()
        for b in m.boxes {
            addBox(x: b.x, z: b.z, w: b.w, h: b.h, l: b.l, color: b.color,
                   solid: b.solid, parent: mapNode, chamfer: b.solid ? 0.08 : 0, base: b.base)
        }

        scene.background.contents = m.sky
        scene.fogColor = m.sky
        scene.fogStartDistance = CGFloat(m.half * 1.5)
        scene.fogEndDistance = CGFloat(m.half * 4.5)
        mapName = m.name
    }

    /// First-person weapon model (with hands), rebuilt when you switch guns.
    func buildGun() {
        gunNode.childNodes.forEach { $0.removeFromParentNode() }
        GunModels.build(weaponIndex, into: gunNode, flash: flashNode)
        setCategory(gunNode, 2)    // category 2: never hit by bullets, never casts shadows
    }

    func setCategory(_ node: SCNNode, _ mask: Int) {
        node.categoryBitMask = mask
        node.castsShadow = false
        node.childNodes.forEach { setCategory($0, mask) }
    }

    /// Re-read the saved loadout. If the weapon in hand is no longer equipped, switch to the primary.
    func applyLoadout() {
        loadout = Loadout.load()
        if !loadout.contains(weaponIndex) {
            weaponIndex = loadout[0]
            buildGun()
        }
    }

    /// `initial` = start of a round (your team's spawn). Otherwise a respawn mid-match, far from the enemies.
    func respawn(initial: Bool = true) {
        applyLoadout()
        applyGraphicsPrefs()
        health = 100
        alive = true
        respawnIn = 0
        lifeKills = 0
        respawnToken += 1
        ammo = Weapon.all.map { $0.magSize }
        reloading = false
        reloadToken += 1
        aiming = false
        let now = ProcessInfo.processInfo.systemUptime
        let sp = (initial || net.practice) ? initialSpawn(for: net.myID) : bestRespawn()
        playerNode.position = SCNVector3(sp.x, 1.6, sp.z)
        yaw = sp.yaw
        pitch = 0
        recoilPitch = 0
        recoilYaw = 0
        bloom = 0
        vel = SIMD2<Float>(0, 0)
        vy = 0
        feetY = 0
        groundY = 0
        eyeY = 1.6
        roll = 0
        sliding = false
        invulnerableUntil = initial ? 0 : now + 1.5       // a moment of safety after a respawn
        equipStart = now                                   // the gun is raised at the start of every life
        equipDuration = 0.45
    }

    // MARK: Shooting
    func currentSpreadDeg() -> Float {
        let w = Weapon.all[weaponIndex]
        if w.melee { return 0 }
        var s = w.spreadHip + (w.spreadAds - w.spreadHip) * adsAmount
        let speed = (vel.x * vel.x + vel.y * vel.y).squareRoot()
        s += w.moveSpread * min(1, speed / 8) * (1 - 0.5 * adsAmount)
        if feetY > groundY + 0.01 { s += w.airSpread }
        if crouching || sliding { s *= 0.7 }
        return s + bloom
    }

    func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        let dx = Float(a.x - b.x), dy = Float(a.y - b.y), dz = Float(a.z - b.z)
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// "p3" or "p3_head" -> 3
    func playerID(fromNodeName name: String) -> Int? {
        guard name.hasPrefix("p") else { return nil }
        return Int(name.dropFirst().prefix(while: { $0 != "_" }))
    }

    func fire() {
        guard phase == .playing, alive, !reloading, !paused, mouseCaptured else { return }
        let w = Weapon.all[weaponIndex]
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextFire else { return }
        if !w.melee && ammo[weaponIndex] <= 0 { reload(); return }
        nextFire = now + w.fireDelay
        if !w.melee { ammo[weaponIndex] -= 1 }
        if now - lastShotTime > 0.3 { shotIndex = 0 }     // the recoil pattern restarts after a pause
        lastShotTime = now

        net.send(.shot(id: net.myID, weapon: weaponIndex), reliable: false)
        playSound(w.sound)
        if !w.melee { muzzleFlash() }
        if [0, 3, 7, 8, 9, 10].contains(weaponIndex) { ejectCasing() }      // rifle and handgun drop brass

        // Spread is worked out BEFORE this shot's recoil, so the first shot is the most accurate
        let spread = currentSpreadDeg()

        // Recoil: climbs with sustained fire, with a repeatable sideways pattern
        let adsMul = 1 - 0.35 * adsAmount
        let idx = Float(shotIndex)
        recoilPitch += w.kickUp * (1 + min(idx, 6) * 0.12) * adsMul
        recoilYaw += (w.kickSide * sin(idx * 2.1 + 0.7) + Float.random(in: -0.15...0.15) * w.kickSide) * adsMul
        recoil = min(0.12, w.kickUp * 3)
        bloom = min(w.maxBloom, bloom + w.bloomPerShot)
        shotIndex += 1
        if !w.melee && ammo[weaponIndex] == 0 { reload() }    // auto-reload when empty

        // Bullets start at the centre of the screen, exactly where the crosshair is
        let from = cameraNode.worldPosition
        let tip = flashNode.worldPosition
        let opts: [String: Any] = [SCNHitTestOption.categoryBitMask.rawValue: 1]
        let rng = CGFloat(w.range)
        var damageBy: [Int: Float] = [:]
        var distBy: [Int: Float] = [:]
        var headIDs = Set<Int>()

        // Melee swings sweep a small cone of rays so close fights are forgiving; guns use one ray per pellet
        let meleeOffsets: [(Float, Float)] = [(0, 0), (0.12, 0), (-0.12, 0), (0, 0.12), (0, -0.12), (0.24, 0), (-0.24, 0), (0, 0.22)]
        let rays = w.melee ? meleeOffsets.count : w.pellets
        for ray in 0..<rays {
            if w.melee && !damageBy.isEmpty { break }
            let ox: Float
            let oy: Float
            if w.melee {
                ox = meleeOffsets[ray].0 * Float(rng)
                oy = meleeOffsets[ray].1 * Float(rng)
            } else {
                let r = tan(spread * Float.pi / 180) * Float.random(in: 0...1).squareRoot()
                let a = Float.random(in: 0..<(2 * Float.pi))
                ox = r * cos(a) * Float(rng)
                oy = r * sin(a) * Float(rng)
            }
            let target = cameraNode.convertPosition(SCNVector3(CGFloat(ox), CGFloat(oy), -rng), to: nil)
            let hits = scene.rootNode.hitTestWithSegment(from: from, to: target, options: opts)

            guard let hit = hits.first else {
                if !w.melee { spawnTracer(from: tip, to: target) }
                continue
            }
            if !w.melee { spawnTracer(from: tip, to: hit.worldCoordinates) }
            let name = hit.node.name ?? ""

            if let id = playerID(fromNodeName: name), remotes[id] != nil, isEnemy(id) {
                let head = name.hasSuffix("_head")
                let dist = distance(from, hit.worldCoordinates)
                let t = max(0, min(1, (dist - w.falloffStart) / max(0.01, w.falloffEnd - w.falloffStart)))
                var dmg = Float(w.damage) * (head ? w.headMul : 1)
                dmg *= 1 - (1 - w.minDamageMul) * t               // damage drops with distance
                if dmg.isFinite { damageBy[id, default: 0] += dmg }
                distBy[id] = dist
                if head { headIDs.insert(id) }
                spawnImpact(at: hit.worldCoordinates, color: NSColor(red: 1, green: 0.3, blue: 0.3, alpha: 1))
            } else if !w.melee {
                spawnImpact(at: hit.worldCoordinates, color: NSColor(white: 0.1, alpha: 1))
            }
        }

        // One hit message per player that was hit (a shotgun can hit several pellets on one player)
        var anyHit = false
        var anyHead = false
        for (id, dmg) in damageBy {
            let amount = Int(dmg.rounded())
            guard amount > 0, let target = remotes[id] else { continue }
            anyHit = true
            if headIDs.contains(id) { anyHead = true }
            target.humanoid.flash()
            lastHit[id] = HitInfo(time: ProcessInfo.processInfo.systemUptime, weapon: weaponIndex,
                                  head: headIDs.contains(id), dist: distBy[id] ?? 0,
                                  sliding: sliding, airborne: feetY > groundY + 0.3, high: feetY >= 2.5)
            if target.isDummy {
                practiceDamage(amount)
            } else if net.isHost, let bot = bots[id] {
                bot.takeDamage(amount, from: net.myID)             // bots live on the host
            } else {
                net.send(.hit(shooter: net.myID, target: id, damage: amount), reliable: true)
            }
        }
        if anyHit {
            showHitMarker(head: anyHead)
            playSound(anyHead ? "Ping" : "Tink")
        }
    }

    /// Practice dummy: it needs a few hits, then counts as a kill.
    func practiceDamage(_ amount: Int) {
        practiceHP -= amount
        guard practiceHP <= 0 else { return }
        practiceHP = 100
        if let i = net.snap.players.firstIndex(where: { $0.id == net.myID }) { net.snap.players[i].kills += 1 }
        playSound("Glass")
        addFeed("You eliminated Dummy", good: true)
    }

    func reload() {
        let i = weaponIndex
        let w = Weapon.all[i]
        guard w.magSize > 0, !reloading, ammo[i] < w.magSize else { return }
        reloading = true
        reloadToken += 1
        reloadStart = ProcessInfo.processInfo.systemUptime
        reloadDuration = w.reloadTime
        let token = reloadToken
        playSound("Bottle")
        DispatchQueue.main.asyncAfter(deadline: .now() + w.reloadTime) { [weak self] in
            guard let self, self.reloadToken == token else { return }
            self.ammo[i] = w.magSize
            self.reloading = false
        }
    }

    func switchWeapon(_ i: Int) {
        guard i != weaponIndex, i >= 0, i < Weapon.all.count else { return }
        weaponIndex = i
        reloading = false
        reloadToken += 1          // cancels any reload in progress
        bloom = 0
        shotIndex = 0
        let now = ProcessInfo.processInfo.systemUptime
        nextFire = now + Weapon.all[i].equipTime
        equipStart = now
        equipDuration = max(0.25, Weapon.all[i].equipTime)
        buildGun()
        playSound("Tink")
    }

    func switchSlot(_ slot: Int) {
        guard slot >= 0, slot < loadout.count else { return }
        switchWeapon(loadout[slot])
    }

    var activeSlot: Int { loadout.firstIndex(of: weaponIndex) ?? 0 }

    func setAim(_ on: Bool) {
        aiming = on
    }

    /// A bound key was pressed.
    func hotkey(_ code: UInt16) {
        func bound(_ a: KeyAction) -> Bool { code == (binds[a] ?? a.defaultCode) }
        if bound(.reload) { reload(); return }
        if bound(.aim) { setAim(Prefs.adsToggle ? !aiming : true); return }
        if bound(.fire) { firing = true; fire(); return }
        if bound(.scoreboard) { showScoreboard = true; return }
        for a in KeyAction.allCases {
            if let slot = a.weaponSlot, bound(a) { switchSlot(slot); return }
        }
        if net.practice {
            if code == 46 {                                         // M: cycle maps in Practice
                loadMap(currentMap + 1)
                net.snap.map = currentMap
                respawn()
            } else if code == 17 {                                  // T: dummy moves / stands still
                practiceMoves.toggle()
            }
        }
    }

    /// A bound key was released.
    func hotkeyUp(_ code: UInt16) {
        if code == (binds[.aim] ?? KeyAction.aim.defaultCode), !Prefs.adsToggle { setAim(false) }
        if code == (binds[.fire] ?? KeyAction.fire.defaultCode) { firing = false }
        if code == (binds[.scoreboard] ?? KeyAction.scoreboard.defaultCode) { showScoreboard = false }
    }

    func slotKeyLabel(_ slot: Int) -> String {
        guard let a = KeyAction.allCases.first(where: { $0.weaponSlot == slot }) else { return "" }
        return Keybinds.label(binds[a] ?? a.defaultCode)
    }

    // MARK: Feedback
    func playSound(_ name: String, volume: Float = 1) {
        SoundBank.shared.play(name, volume: Float(Prefs.volume) * volume)
    }

    func muzzleFlash() {
        flashNode.eulerAngles.z = CGFloat.random(in: 0...CGFloat.pi)
        let sc = CGFloat.random(in: 0.8...1.3)
        flashNode.scale = SCNVector3(sc, sc, sc)
        flashNode.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.flashNode.isHidden = true
        }
    }

    /// A little brass casing flies out of the gun, drops and fades.
    func ejectCasing() {
        let c = SCNNode(geometry: SCNBox(width: 0.012, height: 0.012, length: 0.03, chamferRadius: 0.002))
        c.geometry?.firstMaterial?.diffuse.contents = NSColor(red: 0.9, green: 0.7, blue: 0.2, alpha: 1)
        c.geometry?.firstMaterial?.emission.contents = NSColor(red: 0.3, green: 0.2, blue: 0.0, alpha: 1)
        c.position = gunNode.convertPosition(SCNVector3(0.04, 0.035, -0.12), to: nil)
        c.castsShadow = false
        c.categoryBitMask = 2
        scene.rootNode.addChildNode(c)
        let v = cameraNode.convertVector(SCNVector3(0.5, 0.35, 0.15), to: nil)
        let fall = SCNVector3(v.x * 0.6, -1.4, v.z * 0.6)
        c.runAction(.group([
            .sequence([.move(by: v, duration: 0.18), .move(by: fall, duration: 0.45)]),
            .rotateBy(x: 9, y: 4, z: 6, duration: 0.63),
            .sequence([.wait(duration: 0.5), .fadeOut(duration: 0.13), .removeFromParentNode()])
        ]))
    }

    func spawnImpact(at p: SCNVector3, color: NSColor) {
        let s = SCNNode(geometry: SCNSphere(radius: 0.06))
        s.geometry?.firstMaterial?.diffuse.contents = color
        s.geometry?.firstMaterial?.emission.contents = color
        s.position = p
        s.castsShadow = false
        s.categoryBitMask = 2
        scene.rootNode.addChildNode(s)
        s.runAction(.sequence([.wait(duration: 1.5), .fadeOut(duration: 0.5), .removeFromParentNode()]))
    }

    /// A thin glowing line from the gun to where the bullet landed.
    func spawnTracer(from a: SCNVector3, to b: SCNVector3) {
        let len = distance(a, b)
        guard len > 0.6, len.isFinite else { return }
        let node = SCNNode()
        node.position = a
        scene.rootNode.addChildNode(node)
        node.look(at: b)
        let cyl = SCNCylinder(radius: 0.012, height: CGFloat(len))
        cyl.firstMaterial?.diffuse.contents = NSColor.yellow
        cyl.firstMaterial?.emission.contents = NSColor.yellow
        cyl.firstMaterial?.lightingModel = .constant
        let c = SCNNode(geometry: cyl)
        c.eulerAngles.x = CGFloat.pi / 2
        c.position = SCNVector3(0, 0, -CGFloat(len) / 2)
        node.addChildNode(c)
        setCategory(node, 2)
        node.runAction(.sequence([.wait(duration: 0.03), .fadeOut(duration: 0.06), .removeFromParentNode()]))
    }

    func showHitMarker(head: Bool) {
        hitMarker = true
        headshot = head
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.hitMarker = false
        }
    }

    func flashDamage() {
        damageFlash = 0.45
        playSound("Funk")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.damageFlash = 0
        }
    }

    func addFeed(_ text: String, good: Bool) {
        let item = FeedItem(text: text, good: good)
        feed.append(item)
        if feed.count > 5 { feed.removeFirst() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.feed.removeAll { $0.id == item.id }
        }
    }

    func playRemoteShot(id: Int, weapon: Int) {
        guard let r = remotes[id] else { return }
        let w = Weapon.all[min(max(weapon, 0), Weapon.all.count - 1)]
        if !w.melee { r.humanoid.fireFlash() }
        let dx = r.shownPos.x - Float(playerNode.position.x)
        let dz = r.shownPos.z - Float(playerNode.position.z)
        let dist = (dx * dx + dz * dz).squareRoot()
        playSound(w.sound, volume: max(0.1, 1 - dist / 40))
    }

    func handleKilled(killer: Int, victim: Int) {
        guard killer != victim else { return }
        let kn = net.name(of: killer), vn = net.name(of: victim)
        if killer == net.myID {
            playSound("Glass")
            addFeed("You eliminated \(vn)", good: true)
            registerMyKill(victim: victim)
        } else if victim == net.myID {
            addFeed("\(kn) eliminated you", good: false)
        } else {
            addFeed("\(kn) eliminated \(vn)", good: !isEnemy(killer))
        }
    }

    // MARK: Input
    func installInput() {
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged, .mouseMoved, .leftMouseDragged,
                       .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .scrollWheel]
        ) { [weak self] e in
            guard let self else { return e }
            switch e.type {
            case .keyDown:
                if Keybinds.listening { return e }            // the settings screen is rebinding a key
                e.window?.acceptsMouseMovedEvents = true
                if e.keyCode == 53 {                          // Esc: pause / resume
                    if self.paused { self.resume() } else { self.pause() }
                    return nil
                }
                if self.paused { return e }
                self.keys.insert(e.keyCode)
                if !e.isARepeat { self.hotkey(e.keyCode) }
                return nil
            case .keyUp:
                self.keys.remove(e.keyCode)
                if !self.paused { self.hotkeyUp(e.keyCode) }
                return self.paused ? e : nil
            case .flagsChanged:                               // Shift, Control... count as keys too
                if Keybinds.listening { return e }
                if let flag = Keybinds.modifierFlag(for: e.keyCode) {
                    if e.modifierFlags.contains(flag) {
                        self.keys.insert(e.keyCode)
                        if !self.paused { self.hotkey(e.keyCode) }
                    } else {
                        self.keys.remove(e.keyCode)
                        if !self.paused { self.hotkeyUp(e.keyCode) }
                    }
                }
                return e
            case .mouseMoved, .leftMouseDragged:
                if self.mouseCaptured && !self.paused {
                    self.look(dx: Float(e.deltaX), dy: Float(e.deltaY))
                }
                return e
            case .leftMouseDown:
                if self.paused { return e }
                guard let w = e.window, w.contentLayoutRect.contains(e.locationInWindow) else { return e }
                w.acceptsMouseMovedEvents = true
                if !self.mouseCaptured {                      // first click only grabs the mouse
                    self.captureMouse()
                    return e
                }
                self.firing = true
                self.fire()
                return e
            case .leftMouseUp:
                self.firing = false
                return e
            case .rightMouseDown:                             // aim down sights
                if self.paused || !self.mouseCaptured { return e }
                self.setAim(Prefs.adsToggle ? !self.aiming : true)
                return nil
            case .rightMouseUp:
                if !Prefs.adsToggle { self.setAim(false) }
                return e
            case .scrollWheel:                                // mouse wheel cycles weapons
                if self.paused || !self.mouseCaptured { return e }
                let now = ProcessInfo.processInfo.systemUptime
                if abs(e.scrollingDeltaY) > 1 && now - self.lastScrollSwitch > 0.25 {
                    self.lastScrollSwitch = now
                    let n = self.loadout.count
                    self.switchSlot(((self.activeSlot + (e.scrollingDeltaY > 0 ? -1 : 1)) % n + n) % n)
                }
                return nil
            default:
                return e
            }
        }
    }

    func captureMouse() {
        guard !mouseCaptured else { return }
        mouseCaptured = true
        CGAssociateMouseAndMouseCursorPosition(0)
        NSCursor.hide()
    }

    func releaseMouse() {
        guard mouseCaptured else { return }
        mouseCaptured = false
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
    }

    func pause() {
        guard !paused else { return }
        paused = true
        firing = false
        aiming = false
        showScoreboard = false
        keys.removeAll()
        releaseMouse()
    }

    func resume() {
        binds = Keybinds.load()      // pick up any rebound keys
        applyGraphicsPrefs()
        paused = false
        captureMouse()
    }

    func leave() {
        net.leaveMatch()
    }

    func look(dx: Float, dy: Float) {
        let zoom = 1 + (Weapon.all[weaponIndex].adsFov - 1) * adsAmount
        let k = 0.003 * Float(Prefs.sensitivity) * pow(zoom, 0.7)     // slower turning while zoomed in
        yaw -= dx * k
        pitch = max(-1.4, min(1.4, pitch - dy * k))
        swayYaw = max(-0.06, min(0.06, swayYaw + dx * 0.0007))
        swayPitch = max(-0.06, min(0.06, swayPitch - dy * 0.0007))
    }

    // MARK: Game loop
    /// SceneKit calls this on its render thread. Everything else in the game lives on the main thread,
    /// so we hand the frame over to the main thread (at most one waiting at a time) and do all work there.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime t: TimeInterval) {
        pendingLock.lock()
        if updatePending { pendingLock.unlock(); return }
        updatePending = true
        pendingLock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingLock.lock()
            self.updatePending = false
            self.pendingLock.unlock()
            self.update(now: ProcessInfo.processInfo.systemUptime)
        }
    }

    func update(now: TimeInterval) {
        let dt = Float(min(lastTime == 0 ? 0 : now - lastTime, 0.05))
        lastTime = now

        // On-screen stats
        frames += 1
        if now - lastStatTime >= 1 {
            let elapsed = now - lastStatTime
            if Prefs.showStats {
                var text = "FPS \(Int((Double(frames) / elapsed).rounded()))"
                let rs = remotes.values.filter { !$0.isDummy && $0.playhead != nil }
                if !rs.isEmpty {
                    let delayMs = Int((rs.map { $0.delay }.max() ?? 0) * 1000)
                    let bufMs = Int((rs.map { max(0, $0.latestTs - ($0.playhead ?? 0)) }.min() ?? 0) * 1000)
                    let pkts = rs.reduce(0) { $0 + $1.packetCount }
                    text += "   buffer \(bufMs) ms   delay \(delayMs) ms   \(Int(Double(pkts) / elapsed)) pkt/s"
                }
                stats = text
            } else if !stats.isEmpty {
                stats = ""
            }
            for r in remotes.values { r.packetCount = 0 }
            frames = 0
            lastStatTime = now
        }

        let w = Weapon.all[weaponIndex]
        let live = phase == .playing && alive && !paused
        func down(_ a: KeyAction) -> Bool { keys.contains(binds[a] ?? a.defaultCode) }

        // Input -> wished direction
        var f: Float = 0, s: Float = 0
        if live {
            if down(.forward) { f += 1 }
            if down(.back)    { f -= 1 }
            if down(.right)   { s += 1 }
            if down(.left)    { s -= 1 }
        }
        let grounded = feetY <= groundY + 0.01          // on the floor or on top of a box
        let slideKey = live && down(.slide)
        let sprinting = live && down(.sprint) && f > 0 && !aiming && !sliding

        let fwd = SIMD2<Float>(-sin(yaw), -cos(yaw))
        let right = SIMD2<Float>(cos(yaw), -sin(yaw))
        var wish = fwd * f + right * s
        let wl = (wish.x * wish.x + wish.y * wish.y).squareRoot()
        if wl > 1 { wish /= wl }
        let planar = (vel.x * vel.x + vel.y * vel.y).squareRoot()

        // Sliding: move fast, then press the slide key. You get a burst of speed that fades out.
        // You can aim and shoot the whole time, and jump out of it to keep your momentum.
        slideCooldown = max(0, slideCooldown - dt)
        let slidePressed = slideKey && !wasSlideKey
        wasSlideKey = slideKey
        if slidePressed && grounded && !sliding && slideCooldown <= 0 && planar > 4.5 {
            sliding = true
            slideDir = vel / planar
            slideSpeed = min(13, max(planar * 1.25, 9.5))
        }

        if sliding {
            slideSpeed = max(0, slideSpeed - 4.6 * dt)
            slideDir += wish * dt * 1.6                          // a little steering
            let sl = (slideDir.x * slideDir.x + slideDir.y * slideDir.y).squareRoot()
            if sl > 0.001 { slideDir /= sl }
            vel = slideDir * slideSpeed
            if slideSpeed < 3.2 || !slideKey || !grounded {
                sliding = false
                slideCooldown = 0.35
            }
            crouching = true
        } else {
            let crouched = live && slideKey && grounded
            crouching = crouched
            var speed: Float = sprinting ? 8.5 : 5.5
            speed *= w.moveMul
            speed *= 1 - 0.4 * adsAmount
            if crouched { speed *= 0.5 }
            if grounded {
                vel += (wish * speed - vel) * min(1, dt * 12)
            } else {
                // In the air you keep your momentum and can only steer a little
                var nv = vel + wish * 22 * dt
                let cap = max(speed, planar)
                let nl = (nv.x * nv.x + nv.y * nv.y).squareRoot()
                if nl > cap { nv *= cap / nl }
                vel = nv
            }
        }

        // Jump, then gravity
        if live && down(.jump) && grounded {
            vy = 8.2                                        // about 1.5 high
            if sliding { sliding = false; slideCooldown = 0.35 }
        }
        vy -= 22 * dt
        let prevFeet = feetY
        feetY += vy * dt

        // Move, then keep inside the arena
        var p = SIMD2<Float>(Float(playerNode.position.x), Float(playerNode.position.z))
        p += vel * dt
        let lim = arenaHalf - 1
        p.x = max(-lim, min(lim, p.x))
        p.y = max(-lim, min(lim, p.y))

        // Walls: push the player out of any block that is too tall to step onto (circle vs rectangle)
        let radius: Float = 0.4
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

        // Other players are solid too (when they are at about the same height)
        for r in remotes.values where r.alive && r.hasData {
            let odx = p.x - r.shownPos.x, odz = p.y - r.shownPos.z
            let od = (odx * odx + odz * odz).squareRoot()
            if od < 0.85 && od > 0.0001 && abs(r.shownPos.y - 0.9 - feetY) < 1.2 {
                p.x = r.shownPos.x + odx / od * 0.85
                p.y = r.shownPos.z + odz / od * 0.85
            }
        }

        // Floor: the top of the highest block under your feet that you can step onto, or the ground
        var ground: Float = 0
        for o in obstacles where o.top <= feetY + stepUp
            && abs(p.x - o.x) <= o.hw + 0.2 && abs(p.y - o.z) <= o.hl + 0.2 {
            ground = max(ground, o.top)
        }
        groundY = ground
        if feetY <= ground {                                // landed, or stepped up onto something
            feetY = ground
            if vy < 0 { vy = 0 }
        }
        // Head bump: you can't jump up through a bridge or walkway above you
        if vy > 0 {
            for o in obstacles where o.base > prevFeet + 1.7 && o.base <= feetY + 1.8
                && abs(p.x - o.x) <= o.hw + 0.3 && abs(p.y - o.z) <= o.hl + 0.3 {
                feetY = o.base - 1.8
                vy = 0
                break
            }
        }

        // Aiming, sprint pose, recoil and spread recovery
        let canAim = !w.melee && live && !reloading && !sprinting
        let aimTarget: Float = (aiming && canAim) ? 1 : 0
        adsAmount += (aimTarget - adsAmount) * min(1, dt * 14)
        sprintAmount += ((sprinting ? 1 : 0) - sprintAmount) * min(1, dt * 10)
        recoilPitch -= recoilPitch * min(1, dt * 7)
        recoilYaw -= recoilYaw * min(1, dt * 7)
        recoil *= max(0, 1 - dt * 14)
        swayYaw -= swayYaw * min(1, dt * 9)
        swayPitch -= swayPitch * min(1, dt * 9)
        bloom = max(0, bloom - w.bloomRecover * dt)

        // Camera height: head bob while walking, low when sliding or crouching, on the floor when eliminated
        let moveSpeed = (vel.x * vel.x + vel.y * vel.y).squareRoot()
        if grounded { bobPhase += moveSpeed * dt * 1.7 }
        let bob = sin(bobPhase) * 0.035 * min(1, moveSpeed / 6) * (1 - adsAmount) * (sliding || !grounded ? 0 : 1)
        let targetEye: Float = !alive ? 0.35 : (sliding ? 0.8 : (crouching ? 1.05 : 1.6))
        eyeY += (targetEye - eyeY) * min(1, dt * 9)
        let targetRoll: Float = alive ? 0 : 0.6
        roll += (targetRoll - roll) * min(1, dt * 5)

        playerNode.position = SCNVector3(p.x, feetY + eyeY + bob, p.y)
        playerNode.eulerAngles.y = CGFloat(yaw + recoilYaw)
        cameraNode.eulerAngles.x = CGFloat(max(-1.5, min(1.5, pitch + recoilPitch)))
        cameraNode.eulerAngles.z = CGFloat(roll)

        // Zoom: aiming narrows the field of view, sprinting widens it a little
        let zoom = 1 + (w.adsFov - 1) * adsAmount
        let slideKick: Float = sliding ? 0.04 : 0
        cameraNode.camera?.fieldOfView = CGFloat(Float(Prefs.fov) * zoom * (1 + 0.05 * sprintAmount + slideKick))

        // First-person gun animation: reload dip, equip raise, sway, sprint tilt, recoil, aim
        let reloadAnim: Float = reloading
            ? sin(min(1, Float((now - reloadStart) / max(0.1, reloadDuration))) * Float.pi) : 0
        let eq = min(1, Float((now - equipStart) / max(0.05, equipDuration)))
        let equipAnim = 1 - eq * eq * (3 - 2 * eq)          // 1 -> 0, smooth

        let hip = SIMD3<Float>(0.24, -0.22, -0.42)
        let aimPos = SIMD3<Float>(0, -(Float(w.sightY) + 0.012), -0.36)   // sights line up with the crosshair
        var gp = hip + (aimPos - hip) * adsAmount
        gp.x -= swayYaw * 0.8
        gp.y += bob * 0.6 - 0.05 * sprintAmount - 0.17 * reloadAnim - 0.32 * equipAnim + swayPitch * 0.8
        gp.z += recoil
        gunNode.position = SCNVector3(CGFloat(gp.x), CGFloat(gp.y), CGFloat(gp.z))
        gunNode.eulerAngles = SCNVector3(
            CGFloat(-0.35 * sprintAmount + recoil * 1.2 + 0.55 * reloadAnim - 0.8 * equipAnim),
            CGFloat(0.6 * sprintAmount + swayYaw * 1.5),
            CGFloat(0.3 * reloadAnim))
        gunNode.isHidden = w.scope && adsAmount > 0.8      // the scope overlay replaces the gun

        // Other players
        if let d = remotes[dummyID] {
            // The practice dummy patrols back and forth (press T to stop it)
            var dv = SIMD3<Float>(0, 0, 0)
            if practiceMoves {
                let tt = Float(now)
                d.shownPos = SIMD3<Float>(-4, 0.9, sin(tt * 0.7) * 3)
                dv = SIMD3<Float>(0, 0, cos(tt * 0.7) * 2.1)
            }
            d.shownYaw = .pi / 2
            d.apply(vel: dv, crouch: false, dt: dt)
        }
        updateBots(dt: dt, now: now)
        for r in remotes.values where !r.isDummy { r.step(dt: dt) }
    }

    // MARK: Match flow
    /// Called whenever the host's match state changes (on every player, host included).
    func handleMatch(_ s: MatchSnapshot) {
        syncRemotes()
        if net.isHost { syncBots() }
        if s.map != currentMap { loadMap(s.map) }
        let changed = s.phase != lastPhase
        if s.phase == .playing && lastPhase != .playing { playSound("Hero") }
        if s.phase == .countdown && (changed || s.countdown != lastCountdown) {
            if s.countdown > 0 { playSound("Tink") }
            if s.countdown == 3 {
                respawn(initial: true)
                for b in bots.values { b.respawn(initial: true) }
            }       // a new round: everyone back to their spawn
        }
        if (s.phase == .roundEnd || s.phase == .matchEnd) && lastPhase == .playing {
            let t = myTeam
            roundWon = s.teamScore.indices.contains(t) && s.teamScore[t] > lastTeamScore[t]
            if roundWon && alive && health <= 10 && !net.practice { Trophies.shared.add("closeCalls") }
        }
        if s.phase == .matchEnd && lastPhase != .matchEnd && !net.practice {
            // Match over: count it in my profile and update my ranked points
            let draw = s.winner < 0
            let won = !draw && (s.mode.usesTeams ? s.winner == myTeam : s.winner == net.myID)
            let tr = Trophies.shared
            tr.add("matches")
            if won {
                tr.add("wins")
                if s.mode.usesTeams { tr.add("teamWins") }
            }
            trophyDelta = tr.finishMatch(won: won, draw: draw)
        } else if s.phase != .matchEnd && trophyDelta != nil {
            trophyDelta = nil
        }
        lastPhase = s.phase
        lastCountdown = s.countdown
        lastTeamScore = s.teamScore
    }

    /// Host: send the current match state to everyone, and react to it ourselves.
    func hostPublish() {
        net.broadcastSnapshot()
        handleMatch(net.snap)
    }

    func hostBeginRound() {
        guard net.isHost else { return }
        roundToken += 1
        let token = roundToken
        net.snap.phase = .countdown
        net.snap.countdown = 3
        net.snap.winner = -1
        aliveSet = Set(net.snap.players.map { $0.id })
        hostPublish()
        for i in 1...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i)) { [weak self] in
                guard let self, self.roundToken == token, self.net.snap.phase == .countdown else { return }
                if i == 3 {
                    self.net.snap.phase = .playing
                    self.net.snap.countdown = 0
                    self.startClockIfNeeded()
                } else {
                    self.net.snap.countdown = 3 - i
                }
                self.hostPublish()
            }
        }
    }

    /// Timed modes: a one-second clock that ends the match at zero.
    func startClockIfNeeded() {
        guard net.snap.mode.timeLimit > 0, !net.practice, !clockStarted else { return }
        clockStarted = true
        net.snap.timeLeft = net.snap.mode.timeLimit
        matchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.net.snap.phase == .playing else { return }
            self.net.snap.timeLeft -= 1
            if self.net.snap.timeLeft <= 0 { self.hostEndMatch() } else { self.hostPublish() }
        }
    }

    func hostEndMatch() {
        guard net.isHost, net.snap.phase != .matchEnd else { return }
        roundToken += 1
        matchTimer?.invalidate()
        matchTimer = nil
        let s = net.snap
        var winner = -1
        if s.mode.usesTeams {
            if s.teamScore[0] != s.teamScore[1] { winner = s.teamScore[0] > s.teamScore[1] ? 0 : 1 }
        } else if let top = s.players.max(by: { $0.kills < $1.kills }) {
            let tied = s.players.filter { $0.kills == top.kills }.count > 1
            winner = tied ? -1 : top.id
        }
        net.snap.winner = winner
        net.snap.phase = .matchEnd
        hostPublish()
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            self?.net.returnToRoom()                        // everyone goes back to the room
        }
    }

    /// Elimination: the round ends when only one team has players left standing.
    func checkEliminationEnd() {
        var teams = Set<Int>()
        for p in net.snap.players where aliveSet.contains(p.id) { teams.insert(p.team) }
        if teams.count > 1 { hostPublish(); return }       // the fight goes on
        if let w = teams.first { net.snap.teamScore[w] += 1 }
        if (net.snap.teamScore.max() ?? 0) >= net.snap.mode.target { hostEndMatch(); return }
        roundToken += 1
        let token = roundToken
        net.snap.phase = .roundEnd
        net.snap.round += 1
        hostPublish()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.roundToken == token else { return }
            self.hostBeginRound()
        }
    }

    /// Host: a player died. Update the scores and see if the round or match is over.
    func hostHandleDeath(victim: Int, killer: Int) {
        guard net.isHost, net.snap.phase == .playing,
              let vi = net.snap.players.firstIndex(where: { $0.id == victim }) else { return }
        net.snap.players[vi].deaths += 1
        if let ki = net.snap.players.firstIndex(where: { $0.id == killer }), killer != victim,
           !net.snap.mode.usesTeams || net.snap.players[ki].team != net.snap.players[vi].team {
            net.snap.players[ki].kills += 1
            if net.snap.mode == .teamDeathmatch { net.snap.teamScore[net.snap.players[ki].team] += 1 }
        }
        net.send(.killed(killer: killer, victim: victim), reliable: true)
        handleKilled(killer: killer, victim: victim)
        aliveSet.remove(victim)

        switch net.snap.mode {
        case .elimination:
            checkEliminationEnd()
        case .teamDeathmatch:
            if (net.snap.teamScore.max() ?? 0) >= net.snap.mode.target { hostEndMatch() } else { hostPublish() }
        case .freeForAll:
            if net.snap.players.contains(where: { $0.kills >= net.snap.mode.target }) { hostEndMatch() } else { hostPublish() }
        }
    }

    // MARK: Networking
    func sendState() {
        guard !net.practice else { return }
        if net.snap.players.count > 4 {                     // fewer updates when there are many players
            sendTick += 1
            if sendTick % 2 == 0 { return }
        }
        let p = playerNode.position
        mySeq &+= 1
        sendBotStates()
        net.send(.state(PlayerState(id: net.myID, x: Float(p.x), y: feetY + 0.9, z: Float(p.z),
                                    yaw: yaw, crouch: crouching || sliding, alive: alive,
                                    seq: mySeq, ts: ProcessInfo.processInfo.systemUptime,
                                    pitch: pitch,
                                    scoping: aiming && alive && Weapon.all[weaponIndex].scope && adsAmount > 0.5)),
                 reliable: false)
    }

    func scheduleRespawn() {
        guard net.snap.mode.respawns else { return }
        respawnToken += 1
        let token = respawnToken
        respawnIn = 3
        for i in 1...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i)) { [weak self] in
                guard let self, self.respawnToken == token, !self.alive else { return }
                if self.phase != .playing { self.respawnIn = 0; return }
                self.respawnIn = 3 - i
                if i == 3 { self.respawn(initial: false) }
            }
        }
    }

    func iDied(killer: Int) {
        lastKillerOfMe = killer
        lifeKills = 0
        if !net.practice { Trophies.shared.add("deaths") }
        health = 0
        alive = false
        aiming = false
        firing = false
        playSound("Basso")
        if net.isHost {
            hostHandleDeath(victim: net.myID, killer: killer)
        } else {
            net.send(.died(victim: net.myID, killer: killer), reliable: true)    // tell the host
        }
        scheduleRespawn()
    }

    func handle(_ msg: NetMessage) {
        switch msg {
        case .state(let s):
            if s.id != net.myID { remotes[s.id]?.receive(s) }

        case .shot(let id, let weapon):
            if id != net.myID { playRemoteShot(id: id, weapon: weapon) }

        case .hit(let shooter, let target, let dmg):
            if net.isHost, let bot = bots[target] { bot.takeDamage(dmg, from: shooter); return }
            if target == net.myID { applyHitToMe(shooter: shooter, dmg: dmg) }

        case .died(let victim, let killer):                 // only the host receives this
            if net.isHost { hostHandleDeath(victim: victim, killer: killer) }

        case .killed(let killer, let victim):               // from the host
            if !net.isHost { handleKilled(killer: killer, victim: victim) }

        case .match(let s):                                 // from the host
            handleMatch(s)

        case .welcome, .requestTeam:
            break
        }
    }
}
