//
//  GameView.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 23/11/2026.
//

import SwiftUI
import SceneKit

// MARK: - HUD pieces

/// Crosshair whose gap grows with the current bullet spread.
struct Crosshair: View {
    let gap: Double
    var body: some View {
        let off = CGFloat(gap) + 4
        let xs: [CGFloat] = [0, off, 0, -off]
        let ys: [CGFloat] = [-off, 0, off, 0]
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let vertical = (i % 2 == 0)
                Capsule()
                    .fill(.white)
                    .frame(width: vertical ? 2 : 8, height: vertical ? 8 : 2)
                    .offset(x: xs[i], y: ys[i])
            }
            Circle().fill(.white).frame(width: 2, height: 2)
        }
        .shadow(color: .black.opacity(0.8), radius: 1)
        .animation(.easeOut(duration: 0.08), value: gap)
    }
}

/// Black mask with a round hole, used when aiming a scoped weapon.
struct ScopeOverlay: View {
    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) * 0.42
            ZStack {
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: g.size))
                    p.addEllipse(in: CGRect(x: g.size.width / 2 - r, y: g.size.height / 2 - r,
                                            width: r * 2, height: r * 2))
                }
                .fill(Color.black, style: FillStyle(eoFill: true))
                Rectangle().fill(Color.black).frame(width: 1.5, height: r * 2)
                Rectangle().fill(Color.black).frame(width: r * 2, height: 1.5)
                Circle().stroke(Color.black, lineWidth: 3).frame(width: r * 2, height: r * 2)
                Circle().fill(Color.red).frame(width: 3, height: 3)
            }
        }
        .allowsHitTesting(false)
    }
}

struct HitMarkerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let dirs: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        for (dx, dy) in dirs {
            p.move(to: CGPoint(x: c.x + dx * 7, y: c.y + dy * 7))
            p.addLine(to: CGPoint(x: c.x + dx * 15, y: c.y + dy * 15))
        }
        return p
    }
}

struct HealthBar: View {
    let hp: Int
    var body: some View {
        let clamped = max(0, min(100, hp))
        VStack(alignment: .leading, spacing: 4) {
            Text("\(clamped)")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.4))
                Capsule()
                    .fill(clamped > 50 ? Color.green : (clamped > 25 ? Color.yellow : Color.red))
                    .frame(width: 220 * CGFloat(clamped) / 100)
            }
            .frame(width: 220, height: 10)
        }
        .animation(.easeOut(duration: 0.2), value: hp)
    }
}

/// The player list: kills and deaths. Hold Tab to show it, and it appears at the end of a match.
struct ScoreboardView: View {
    let world: GameWorld

    var body: some View {
        let s = world.net.snap
        let rows = s.players.sorted { ($0.kills, -$0.deaths) > ($1.kills, -$1.deaths) }
        VStack(spacing: 8) {
            Text(s.mode.title.uppercased())
                .font(.system(size: 16, weight: .heavy, design: .rounded))
            HStack {
                Text("PLAYER").frame(maxWidth: .infinity, alignment: .leading)
                Text("K").frame(width: 44)
                Text("D").frame(width: 44)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .opacity(0.6)
            ForEach(rows) { p in
                HStack(spacing: 8) {
                    if s.mode.usesTeams {
                        Circle()
                            .fill(p.team == world.myTeam ? Color(red: 0.3, green: 0.6, blue: 1.0)
                                                         : Color(red: 1.0, green: 0.36, blue: 0.4))
                            .frame(width: 10, height: 10)
                    }
                    Text(p.id == world.net.myID ? "\(p.name) (you)" : p.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(p.kills)").frame(width: 44)
                    Text("\(p.deaths)").frame(width: 44)
                }
                .font(.system(size: 14, weight: p.id == world.net.myID ? .heavy : .semibold, design: .rounded))
            }
            if world.phase == .matchEnd, let d = world.trophyDelta {
                Text(d > 0 ? "+\(d) TROPHIES" : (d < 0 ? "\(d) TROPHIES" : "NO TROPHY CHANGE"))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(d > 0 ? Color.yellow : Color.white.opacity(0.7))
                    .padding(.top, 6)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.white)
    }
}

/// The 3D view. It never changes, so SwiftUI is told never to rebuild it when the HUD updates.
struct SceneLayer: View, Equatable {
    let scene: SCNScene
    let camera: SCNNode
    let delegate: SCNSceneRendererDelegate

    static func == (lhs: SceneLayer, rhs: SceneLayer) -> Bool { true }

    var body: some View {
        SceneView(scene: scene,
                  pointOfView: camera,
                  options: [.rendersContinuously],
                  preferredFramesPerSecond: 60,
                  antialiasingMode: .multisampling2X,
                  delegate: delegate)
    }
}

// MARK: - Game screen

struct GameView: View {
    @StateObject private var world: GameWorld
    init(net: GameNetwork) { _world = StateObject(wrappedValue: GameWorld(net: net)) }

    var bannerText: String {
        switch world.phase {
        case .waiting:   return "GET READY"
        case .countdown: return "\(world.net.snap.countdown)"
        case .playing:   return world.alive ? "" : "ELIMINATED"
        case .roundEnd:  return world.roundWon ? "ROUND WON" : "ROUND LOST"
        case .matchEnd:  return world.matchResultText
        }
    }

    var subtitleText: String {
        switch world.phase {
        case .countdown:
            return world.mode == .elimination ? "ROUND \(world.net.snap.round)" : world.mode.title.uppercased()
        case .playing:
            return (!world.alive && world.respawnIn > 0) ? "Respawning in \(world.respawnIn)" : ""
        case .matchEnd:
            return "Back to the room soon..."
        default:
            return ""
        }
    }

    var scorePill: some View {
        HStack(spacing: 14) {
            if world.mode.usesTeams {
                Text(world.leftLabel).font(.system(size: 13, weight: .bold, design: .rounded))
                Text("\(world.allyScore)").font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("—").opacity(0.6)
                Text("\(world.enemyScore)").font(.system(size: 30, weight: .heavy, design: .rounded))
                Text(world.rightLabel).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
            } else {
                Text("KILLS").font(.system(size: 13, weight: .bold, design: .rounded))
                Text("\(world.myKills)").font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("TOP").font(.system(size: 13, weight: .bold, design: .rounded)).opacity(0.7)
                Text("\(world.topKills)").font(.system(size: 30, weight: .heavy, design: .rounded))
            }
            if let t = world.timeText {
                Text(t).font(.system(size: 16, weight: .bold, design: .monospaced))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.black.opacity(0.4), in: Capsule())
    }

    var killFeed: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(world.feed) { item in
                Text(item.text)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(item.good ? Color.green : Color.red)
            }
        }
    }

    var ammoBlock: some View {
        let w = Weapon.all[world.weaponIndex]
        let count = world.ammo[world.weaponIndex]
        return VStack(alignment: .trailing, spacing: 2) {
            Text(w.name.uppercased())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .opacity(0.85)
            if w.melee {
                Text("—")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
            } else {
                Text(world.reloading ? "RELOADING" : "\(count)")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(world.reloading ? Color.yellow : (count <= 3 ? Color.red : Color.white))
                Text("/ \(w.magSize)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .opacity(0.7)
            }
            HStack(spacing: 6) {
                ForEach(0..<world.loadout.count, id: \.self) { slot in
                    let selected = world.loadout[slot] == world.weaponIndex
                    VStack(spacing: 1) {
                        Text(world.slotKeyLabel(slot))
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                        Text(Weapon.all[world.loadout[slot]].name.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    }
                    .frame(minWidth: 62)
                    .padding(.vertical, 4)
                    .background(selected ? Color.white : Color.black.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                }
            }
        }
    }

    var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
            VStack(spacing: 16) {
                Text("PAUSED")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                Text(world.net.practice ? "Practice mode:  M changes map,  T stops the dummy"
                                        : "The match keeps running while you are paused.")
                    .opacity(0.7)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("LOADOUT  (changes apply next round or respawn)")
                            .font(.caption.bold())
                            .opacity(0.7)
                        LoadoutPicker()
                        Divider()
                        SettingsForm()
                    }
                    .padding(.horizontal, 8)
                }
                .frame(width: 600, height: 340)
                HStack(spacing: 12) {
                    Button("Resume") { world.resume() }
                        .buttonStyle(.borderedProminent)
                    Button("Leave match") { world.leave() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
                .controlSize(.large)
            }
            .foregroundStyle(.white)
        }
        .environment(\.colorScheme, .dark)
    }

    var body: some View {
        ZStack {
            Color.black
            SceneLayer(scene: world.scene, camera: world.cameraNode, delegate: world)
                .equatable()

            // Scope view for the sniper
            if world.scoped {
                ScopeOverlay()
            }

            // Red flash when you take damage, red vignette when low on health
            Color.red
                .opacity(world.damageFlash)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.35), value: world.damageFlash)
            RadialGradient(colors: [.clear, Color.red.opacity(0.55)],
                           center: .center, startRadius: 250, endRadius: 800)
                .opacity(world.health < 30 && world.alive ? 1 : 0)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.4), value: world.health)

            // Crosshair: its own layer, so it sits exactly in the middle of the screen where bullets go
            ZStack {
                if !world.scoped && world.alive {
                    Crosshair(gap: world.crosshairGap)
                }
                if world.hitMarker {
                    HitMarkerShape()
                        .stroke(world.headshot ? Color.yellow : Color.red, lineWidth: 3)
                        .frame(width: 40, height: 40)
                }
            }
            .allowsHitTesting(false)

            // HUD
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(world.mapName.uppercased())
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .opacity(0.8)
                        if !world.stats.isEmpty {
                            Text(world.stats)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 4) {
                        scorePill
                        if world.mode == .elimination && !world.net.practice {
                            Text("ALIVE   \(world.alliesAlive)  v  \(world.enemiesAlive)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .opacity(0.9)
                        }
                    }

                    killFeed
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding()

                Spacer()

                VStack(spacing: 4) {
                    Text(bannerText)
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .shadow(color: .black.opacity(0.6), radius: 4)
                    Text(subtitleText)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .opacity(0.85)
                }
                .padding(.bottom, 90)

                if !world.mouseCaptured && !world.paused {
                    Text("Click to start aiming")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                }

                Spacer()

                HStack(alignment: .bottom) {
                    HealthBar(hp: world.health)
                    Spacer()
                    ammoBlock
                }
                .padding()
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 2)     // keeps the HUD readable on the light map
            .allowsHitTesting(false)

            // Scoreboard (hold Tab, and at the end of a match)
            if world.showScoreboard || world.phase == .matchEnd {
                ScoreboardView(world: world)
                    .allowsHitTesting(false)
            }

            // Warnings and trophy banners
            if let bearing = world.sniperThreat, world.alive, !world.paused {
                SniperWarning(bearing: bearing)
            }
            if let toast = world.toast {
                VStack {
                    TrophyToast(toast: toast)
                        .padding(.top, 110)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if world.paused {
                pauseOverlay
            }
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}
