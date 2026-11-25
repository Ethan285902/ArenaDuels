//
//  NetMessage.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 23/11/2026.
//

import Foundation

enum Phase: String, Codable {
    case waiting, countdown, playing, roundEnd, matchEnd
}

enum GameMode: String, Codable, CaseIterable, Identifiable {
    case elimination, teamDeathmatch, freeForAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .elimination:    return "Elimination"
        case .teamDeathmatch: return "Team Deathmatch"
        case .freeForAll:     return "Free For All"
        }
    }

    var blurb: String {
        switch self {
        case .elimination:    return "Teams, rounds, no respawns. Last team standing wins the round. First to 5 rounds wins."
        case .teamDeathmatch: return "Teams. Respawn after 3 seconds. First team to 25 kills wins, or most kills after 5 minutes."
        case .freeForAll:     return "Every player for themselves. Respawn after 3 seconds. First to 15 kills, or most kills after 5 minutes."
        }
    }

    var usesTeams: Bool { self != .freeForAll }
    var respawns: Bool { self != .elimination }

    /// Rounds (elimination) or kills (the other modes) needed to win.
    var target: Int {
        switch self {
        case .elimination:    return 5
        case .teamDeathmatch: return 25
        case .freeForAll:     return 15
        }
    }

    /// Seconds, 0 = no time limit.
    var timeLimit: Int {
        switch self {
        case .elimination:    return 0
        case .teamDeathmatch: return 300
        case .freeForAll:     return 300
        }
    }
}

struct PlayerInfo: Codable, Identifiable {
    var id: Int
    var name: String
    var team: Int            // 0 or 1 (ignored in Free For All)
    var kills = 0
    var deaths = 0
    var isBot = false         // computer-controlled (the host runs it)
}

/// Everything about the match that all players must agree on. The host owns it and sends it to everyone.
struct MatchSnapshot: Codable {
    var mode: GameMode = .elimination
    var map: Int = 0
    var phase: Phase = .waiting          // .waiting = still in the room
    var countdown: Int = 3
    var timeLeft: Int = 0                // seconds left, only used by timed modes
    var round: Int = 1
    var teamScore: [Int] = [0, 0]        // rounds won (elimination) or kills (team deathmatch)
    var winner: Int = -1                 // winning team, or winning player id in free for all. -1 = draw
    var players: [PlayerInfo] = []
}

struct PlayerState: Codable {
    var id: Int
    var x: Float, y: Float, z: Float      // body centre
    var yaw: Float
    var crouch: Bool                      // crouching or sliding
    var alive: Bool
    var seq: UInt32                       // increases with every update, so old ones can be dropped
    var ts: Double                        // the sender's clock when this was sent (used for smooth playback)
    var pitch: Float                      // how far up or down they are looking
    var scoping: Bool                     // looking through a sniper scope (others see a glint)
}

enum NetMessage: Codable {
    case state(PlayerState)                                    // anyone -> everyone
    case shot(id: Int, weapon: Int)                            // "this player fired" (sound and muzzle flash)
    case hit(shooter: Int, target: Int, damage: Int)           // shooter -> everyone (only the target reacts)
    case died(victim: Int, killer: Int)                        // victim -> host
    case killed(killer: Int, victim: Int)                      // host -> everyone (kill feed)
    case match(MatchSnapshot)                                  // host -> everyone
    case welcome(id: Int)                                      // host -> a player who just joined
    case requestTeam(id: Int, team: Int)                       // player -> host (in the room)
}
