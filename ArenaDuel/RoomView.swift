//
//  RoomView.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 24/11/2026.
//

import SwiftUI

private let ink = Color(red: 0.13, green: 0.18, blue: 0.32)
private let green = Color(red: 0.2, green: 0.78, blue: 0.4)
private let blue = Color(red: 0.25, green: 0.55, blue: 0.98)
private let orange = Color(red: 1.0, green: 0.6, blue: 0.2)
private let red = Color(red: 0.92, green: 0.34, blue: 0.34)

private func teamColor(_ team: Int) -> Color { team == 0 ? blue : orange }

/// The waiting room: players gather here, the host picks the mode and map, then starts the match.
struct RoomView: View {
    @ObservedObject var net: GameNetwork

    var mode: GameMode { net.snap.mode }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.45, green: 0.72, blue: 1.0),
                                    Color(red: 0.80, green: 0.92, blue: 1.0)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("ROOM")
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: Color(red: 0.12, green: 0.32, blue: 0.72), radius: 0, x: 0, y: 6)
                        Text("\(net.snap.players.count) / \(GameNetwork.maxPlayers) PLAYERS")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(3)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    card
                }
                .padding(32)
            }
        }
        .frame(minWidth: 800, minHeight: 760)
    }

    // MARK: Pieces

    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(ink.opacity(0.5))
    }

    func modeCard(_ m: GameMode) -> some View {
        let selected = mode == m
        return Button { net.setMode(m) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(m.title.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(ink)
                Text(m.blurb)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.6))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(selected ? blue.opacity(0.14) : Color.black.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? blue : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!net.isHost)
    }

    func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }

    func playerRow(_ p: PlayerInfo) -> some View {
        HStack(spacing: 10) {
            Text(String(p.name.prefix(1)).uppercased())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(mode.usesTeams ? teamColor(p.team) : blue, in: Circle())
            Text(p.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
            if p.id == net.myID { chip("YOU", green) }
            if p.id == 0 { chip("HOST", ink) }
            if p.isBot { chip("BOT", Color.gray) }
            Spacer()
        }
        .padding(8)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    func teamColumn(_ team: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(team == 0 ? "TEAM BLUE" : "TEAM ORANGE")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(teamColor(team))
            ForEach(net.snap.players.filter { $0.team == team }) { playerRow($0) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var card: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                sectionTitle("GAME MODE")
                HStack(alignment: .top, spacing: 10) {
                    ForEach(GameMode.allCases) { modeCard($0) }
                }
            }

            VStack(spacing: 8) {
                sectionTitle("MAP")
                if net.isHost {
                    HStack(spacing: 6) {
                        ForEach(0..<ArenaMap.all.count, id: \.self) { i in
                            Button { net.setMap(i) } label: {
                                MapCard(map: ArenaMap.all[i], selected: net.snap.map == i)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    MapCard(map: ArenaMap.all[net.snap.map % ArenaMap.all.count], selected: true)
                }
            }

            VStack(spacing: 8) {
                sectionTitle("PLAYERS")
                if mode.usesTeams {
                    HStack(alignment: .top, spacing: 14) {
                        teamColumn(0)
                        teamColumn(1)
                    }
                } else {
                    VStack(spacing: 6) {
                        ForEach(net.snap.players) { playerRow($0) }
                    }
                }
            }

            if net.isHost {
                VStack(spacing: 8) {
                    sectionTitle("BOTS")
                    HStack(spacing: 10) {
                        Button { net.setBotCount(net.botCount - 1) } label: { Image(systemName: "minus") }
                            .buttonStyle(.bordered)
                        Text("\(net.botCount)")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(ink)
                            .frame(minWidth: 30)
                        Button { net.setBotCount(net.botCount + 1) } label: { Image(systemName: "plus") }
                            .buttonStyle(.bordered)
                        Button("FILL ROOM") { net.fillWithBots() }
                            .buttonStyle(.bordered)
                    }
                    Picker("Bot difficulty", selection: $net.botDifficulty) {
                        Text("Easy").tag(0)
                        Text("Normal").tag(1)
                        Text("Hard").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                    Text("Bots step aside when real players join.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(ink.opacity(0.45))
                }
            }

            VStack(spacing: 12) {
                if net.isHost {
                    Button("START MATCH") { net.beginMatch() }
                        .buttonStyle(BigButtonStyle(color: green))
                        .disabled(!net.canStart)
                        .opacity(net.canStart ? 1 : 0.45)
                    if !net.canStart {
                        Text("Add bots above, or have another player press FIND A MATCH on their Mac.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(ink.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for the host to start...")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(ink.opacity(0.7))
                }

                HStack(spacing: 12) {
                    if mode.usesTeams {
                        Button("SWITCH TEAM") {
                            let mine = net.snap.players.first { $0.id == net.myID }?.team ?? 0
                            net.requestTeam(1 - mine)
                        }
                        .buttonStyle(BigButtonStyle(color: blue))
                    }
                    Button("LEAVE") { net.leaveMatch() }
                        .buttonStyle(BigButtonStyle(color: red))
                }
            }
        }
        .padding(28)
        .frame(width: 600)
        .background(.white, in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: Color(red: 0.1, green: 0.25, blue: 0.6).opacity(0.25), radius: 24, y: 10)
    }
}
