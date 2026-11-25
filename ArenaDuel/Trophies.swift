//
//  Trophies.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 26/11/2026.
//

import Combine
import SwiftUI

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let stat: String          // which counter this trophy watches
    let goal: Int
}

/// What happened on my last hit on a player, so a kill can be credited properly.
struct HitInfo {
    let time: TimeInterval
    let weapon: Int
    let head: Bool
    let dist: Float
    let sliding: Bool
    let airborne: Bool
    let high: Bool
}

struct RankInfo {
    let name: String
    let color: Color
    let min: Int
}

/// Your profile: lifetime stats, unlocked trophies and ranked trophy points. Saved on this Mac.
final class Trophies: ObservableObject {
    static let shared = Trophies()

    static let ranks: [RankInfo] = [
        RankInfo(name: "Bronze", color: Color(red: 0.80, green: 0.50, blue: 0.25), min: 0),
        RankInfo(name: "Silver", color: Color(red: 0.70, green: 0.74, blue: 0.80), min: 100),
        RankInfo(name: "Gold", color: Color(red: 1.00, green: 0.80, blue: 0.20), min: 250),
        RankInfo(name: "Platinum", color: Color(red: 0.40, green: 0.85, blue: 0.85), min: 450),
        RankInfo(name: "Diamond", color: Color(red: 0.45, green: 0.65, blue: 1.00), min: 700),
        RankInfo(name: "Champion", color: Color(red: 0.95, green: 0.40, blue: 0.55), min: 1000),
    ]

    static let all: [Achievement] = [
        Achievement(id: "first_blood", title: "First Blood", detail: "Get your first kill", stat: "kills", goal: 1),
        Achievement(id: "rookie", title: "Rookie", detail: "Get 10 kills", stat: "kills", goal: 10),
        Achievement(id: "veteran", title: "Veteran", detail: "Get 100 kills", stat: "kills", goal: 100),
        Achievement(id: "legend", title: "Legend", detail: "Get 500 kills", stat: "kills", goal: 500),
        Achievement(id: "headhunter", title: "Headhunter", detail: "Get 25 headshot kills", stat: "headshotKills", goal: 25),
        Achievement(id: "long_shot", title: "Long Shot", detail: "Kill someone with the sniper from 50+ metres", stat: "longShots", goal: 1),
        Achievement(id: "sniper_elite", title: "Sniper Elite", detail: "Get 25 sniper kills", stat: "sniperKills", goal: 25),
        Achievement(id: "close_quarters", title: "Close Quarters", detail: "Get 25 shotgun kills", stat: "shotgunKills", goal: 25),
        Achievement(id: "blade", title: "Blade Dancer", detail: "Get 10 knife or katana kills", stat: "meleeKills", goal: 10),
        Achievement(id: "slide_tackle", title: "Slide Tackle", detail: "Get a kill while sliding", stat: "slideKills", goal: 1),
        Achievement(id: "air_strike", title: "Air Strike", detail: "Get a kill while in the air", stat: "airKills", goal: 1),
        Achievement(id: "high_ground", title: "High Ground", detail: "Get 10 kills from a roof or walkway", stat: "highGroundKills", goal: 10),
        Achievement(id: "hat_trick", title: "Hat Trick", detail: "Get 3 kills in one life", stat: "tripleKills", goal: 1),
        Achievement(id: "rampage", title: "Rampage", detail: "Get 5 kills in one life", stat: "fiveKills", goal: 1),
        Achievement(id: "payback", title: "Payback", detail: "Kill the player who just killed you", stat: "revenge", goal: 1),
        Achievement(id: "bot_buster", title: "Bot Buster", detail: "Get 50 kills against bots", stat: "botKills", goal: 50),
        Achievement(id: "close_call", title: "Close Call", detail: "Win a round with 10 health or less", stat: "closeCalls", goal: 1),
        Achievement(id: "winner", title: "Winner", detail: "Win a match", stat: "wins", goal: 1),
        Achievement(id: "champion", title: "Champion", detail: "Win 10 matches", stat: "wins", goal: 10),
        Achievement(id: "squad_goals", title: "Squad Goals", detail: "Win a team match", stat: "teamWins", goal: 1),
        Achievement(id: "regular", title: "Regular", detail: "Play 25 matches", stat: "matches", goal: 25),
    ]

    @Published private(set) var stats: [String: Int] = [:]
    @Published private(set) var unlocked: Set<String> = []
    @Published private(set) var points = 0
    var onUnlock: ((Achievement) -> Void)?

    private struct Saved: Codable {
        var stats: [String: Int]
        var unlocked: [String]
        var points: Int
    }

    init() { load() }

    var rank: RankInfo { Trophies.ranks.last(where: { points >= $0.min }) ?? Trophies.ranks[0] }
    var nextRank: RankInfo? { Trophies.ranks.first(where: { $0.min > points }) }

    func stat(_ key: String) -> Int { stats[key] ?? 0 }

    func add(_ key: String, _ n: Int = 1) {
        stats[key, default: 0] += n
        for a in Trophies.all where !unlocked.contains(a.id) && stat(a.stat) >= a.goal {
            unlocked.insert(a.id)
            onUnlock?(a)
        }
        save()
    }

    /// Ranked points at the end of a match: +30 for a win, -15 for a loss (never below 0). Returns the change.
    func finishMatch(won: Bool, draw: Bool) -> Int {
        let raw = draw ? 0 : (won ? 30 : -15)
        let new = max(0, points + raw)
        let delta = new - points
        points = new
        save()
        return delta
    }

    private func save() {
        let s = Saved(stats: stats, unlocked: Array(unlocked), points: points)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: "profile") }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "profile"),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        stats = s.stats
        unlocked = Set(s.unlocked)
        points = s.points
    }
}

/// Your rank, lifetime stats and every trophy with its progress.
struct TrophiesView: View {
    @ObservedObject private var t = Trophies.shared

    var rankCard: some View {
        let r = t.rank
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(r.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name.uppercased())
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text("\(t.points) trophy points")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                }
                Spacer()
            }
            if let next = t.nextRank {
                ProgressView(value: Double(t.points - r.min), total: Double(next.min - r.min))
                Text("\(next.min - t.points) more to reach \(next.name)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.6)
            } else {
                Text("Top rank reached")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.6)
            }
            Text("Win a match: +30.  Lose a match: -15.  Practice does not count.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opacity(0.6)
            HStack(spacing: 18) {
                statBox("KILLS", t.stat("kills"))
                statBox("HEADSHOTS", t.stat("headshotKills"))
                statBox("DEATHS", t.stat("deaths"))
                statBox("MATCHES", t.stat("matches"))
                statBox("WINS", t.stat("wins"))
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    func statBox(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(size: 18, weight: .heavy, design: .rounded))
            Text(label).font(.system(size: 9, weight: .bold, design: .rounded)).opacity(0.6)
        }
    }

    func row(_ a: Achievement) -> some View {
        let done = t.unlocked.contains(a.id)
        let have = min(t.stat(a.stat), a.goal)
        return HStack(spacing: 12) {
            Image(systemName: done ? "trophy.fill" : "trophy")
                .font(.system(size: 22))
                .foregroundStyle(done ? Color.yellow : Color.gray)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(a.detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.65)
                if !done {
                    ProgressView(value: Double(have), total: Double(a.goal))
                        .frame(maxWidth: 240)
                }
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text("\(have) / \(a.goal)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .opacity(0.6)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(done ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            rankCard
            Text("TROPHIES  \(t.unlocked.count) / \(Trophies.all.count)")
                .font(.caption.bold())
                .opacity(0.6)
            ForEach(Trophies.all) { row($0) }
        }
    }
}
