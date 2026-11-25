//
//  ContentView.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 23/11/2026.
//

import SwiftUI
import MultipeerConnectivity

private let ink = Color(red: 0.13, green: 0.18, blue: 0.32)
private let green = Color(red: 0.2, green: 0.78, blue: 0.4)
private let blue = Color(red: 0.25, green: 0.55, blue: 0.98)
private let purple = Color(red: 0.6, green: 0.45, blue: 0.95)
private let orange = Color(red: 1.0, green: 0.6, blue: 0.2)

/// Chunky rounded button that presses down like a toy.
struct BigButtonStyle: ButtonStyle {
    let color: Color
    var vertical: CGFloat = 14
    var size: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity)
            .background(color, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: color.opacity(0.45), radius: 0, x: 0, y: configuration.isPressed ? 1 : 4)
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct KeyChip: View {
    let key: String
    let label: String
    init(_ key: String, _ label: String) { self.key = key; self.label = label }

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(ink)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

struct MapCard: View {
    let map: ArenaMap
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                Color(nsColor: map.sky)
                Color(nsColor: map.accent).frame(height: 4)
                Color.white.frame(height: 24)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))

            Text(map.name.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(ink)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16)
            .fill(selected ? Color(nsColor: map.accent).opacity(0.14) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(selected ? Color(nsColor: map.accent) : Color.black.opacity(0.08),
                    lineWidth: selected ? 3 : 1))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
    }
}

enum LobbySheet: String, Identifiable {
    case settings, loadout, trophies
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var net = GameNetwork()
    @State private var sheet: LobbySheet?
    private let myName = Host.current().localizedName ?? "Player"

    var body: some View {
        if net.matchStarted {
            GameView(net: net)
        } else if net.inRoom {
            RoomView(net: net)
        } else {
            lobby
        }
    }

    var loadoutSummary: String {
        Loadout.load().map { Weapon.all[$0].name }.joined(separator: "  •  ")
    }

    // MARK: Lobby

    @ObservedObject private var trophies = Trophies.shared

    var lobby: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.45, green: 0.72, blue: 1.0),
                                    Color(red: 0.80, green: 0.92, blue: 1.0)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Circle().fill(.white.opacity(0.22)).frame(width: 420, height: 420).offset(x: -420, y: -200)
            Circle().fill(.white.opacity(0.16)).frame(width: 300, height: 300).offset(x: 440, y: 260)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 10)
                centerStage
                Spacer(minLength: 10)
                bottomBar
            }
        }
        .clipped()
        .frame(minWidth: 800, minHeight: 700)
        .sheet(item: $sheet) { which in
            VStack(spacing: 20) {
                Text(which == .settings ? "Settings" : (which == .loadout ? "Loadout" : "Trophies")).font(.title2.bold())
                ScrollView {
                    Group {
                        switch which {
                        case .settings: SettingsForm()
                        case .loadout:  LoadoutPicker()
                        case .trophies: TrophiesView()
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 440)
                Button("Done") { sheet = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(30)
            .frame(width: 620)
        }
    }

    // Top: player on the left, trophy count on the right
    var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(String(myName.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(blue, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(myName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(trophies.rank.name.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(trophies.rank.color)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.vertical, 6)
            .background(.white.opacity(0.9), in: Capsule())

            Spacer()

            Button { sheet = .trophies } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.18))
                    Text("\(trophies.points)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(red: 0.14, green: 0.2, blue: 0.4).opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // Middle: title, arena picker, one big button
    var centerStage: some View {
        VStack(spacing: 22) {
            Text("ARENA DUEL")
                .font(.system(size: 60, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color(red: 0.12, green: 0.32, blue: 0.72), radius: 0, x: 0, y: 6)

            mapPicker

            VStack(spacing: 12) {
                if let notice = net.notice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                }
                if !net.status.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(net.status).font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                }

                Button("BATTLE") { net.host() }
                    .buttonStyle(BigButtonStyle(color: green, vertical: 20, size: 26))
                    .frame(width: 320)

                HStack(spacing: 22) {
                    Button { net.browse() } label: {
                        Label("Join a friend", systemImage: "person.2.fill")
                    }
                    Button { net.startPractice() } label: {
                        Label("Practice", systemImage: "scope")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color(red: 0.12, green: 0.32, blue: 0.72).opacity(0.5), radius: 0, x: 0, y: 2)
            }

            if !net.foundPeers.isEmpty { peerList }
        }
    }

    // One arena shown big, with arrows to change it
    var mapPicker: some View {
        let count = ArenaMap.all.count
        let m = ArenaMap.all[net.selectedMap % count]
        return HStack(spacing: 14) {
            arrow("chevron.left") { net.selectedMap = (net.selectedMap + count - 1) % count }
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Color(nsColor: m.sky)
                    Color.white.opacity(0.55).frame(height: 28)
                    Color(nsColor: m.accent).frame(height: 5).offset(y: -28)
                }
                .frame(height: 70)
                VStack(spacing: 1) {
                    Text(m.name.uppercased())
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(ink)
                    Text("\(net.selectedMap + 1) / \(count)  •  host's map is used")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink.opacity(0.5))
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.white)
            }
            .frame(width: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color(red: 0.1, green: 0.25, blue: 0.6).opacity(0.25), radius: 10, y: 5)
            arrow("chevron.right") { net.selectedMap = (net.selectedMap + 1) % count }
        }
    }

    func arrow(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(ink)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.9), in: Circle())
        }
        .buttonStyle(.plain)
    }

    var peerList: some View {
        VStack(spacing: 8) {
            ForEach(net.foundPeers, id: \.self) { peer in
                HStack(spacing: 12) {
                    Text(String(peer.displayName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(blue, in: Circle())
                    Text(peer.displayName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Spacer()
                    Button("JOIN") { net.invite(peer) }
                        .buttonStyle(BigButtonStyle(color: green, vertical: 7))
                        .frame(width: 80)
                }
                .padding(10)
                .frame(width: 340)
                .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // Bottom: tab bar
    var bottomBar: some View {
        HStack(spacing: 0) {
            tab("Loadout", "scope", loadoutSummary == "" ? "" : Weapon.all[Loadout.load()[0]].name) { sheet = .loadout }
            tab("Trophies", "trophy.fill", trophies.rank.name) { sheet = .trophies }
            tab("Settings", "gearshape.fill", "Keys & more") { sheet = .settings }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.14, green: 0.2, blue: 0.4).opacity(0.9))
    }

    func tab(_ title: String, _ icon: String, _ sub: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 22, weight: .bold))
                Text(title.uppercased()).font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1)
                Text(sub).font(.system(size: 9, weight: .semibold, design: .rounded)).opacity(0.6)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
