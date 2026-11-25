//
//  GameNetwork.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 23/11/2026.
//

import Combine
import MultipeerConnectivity

/// Networking for up to 8 players. The host is in the middle: everyone else sends to the host,
/// and the host passes messages on to the other players. The host also keeps the official match state.
final class GameNetwork: NSObject, ObservableObject {
    static let maxPlayers = 8

    private let serviceType = "arenaduel"
    private let myPeer = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private lazy var session: MCSession = {
        let s = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .none)   // no encryption: lower latency
        s.delegate = self
        return s
    }()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var hostPeer: MCPeerID?                  // players: the host we joined
    private var peerIDs: [MCPeerID: Int] = [:]       // host: which player id belongs to which connection
    private var nextID = 1

    @Published var foundPeers: [MCPeerID] = []
    @Published var inRoom = false                    // in a room (host or player)
    @Published var matchStarted = false              // switches to the game screen
    @Published var isHost = false
    @Published var notice: String?                   // shown in the lobby, e.g. "The host left the match."
    @Published var status = ""
    @Published var selectedMap = 0                   // the map picked in the lobby before hosting
    @Published var selectedMode: GameMode = .elimination
    @Published var botDifficulty = 1                 // 0 easy, 1 normal, 2 hard (bots run on the host)
    @Published var snap = MatchSnapshot()            // the official match state (the host's copy is the truth)

    var myID = 0
    var practice = false
    var onMessage: ((NetMessage) -> Void)?
    var onPlayerLeft: ((Int) -> Void)?

    var myName: String { myPeer.displayName }

    func name(of id: Int) -> String {
        snap.players.first { $0.id == id }?.name ?? (id == 100 ? "Dummy" : "Player")
    }

    var canStart: Bool {
        guard snap.players.count >= 2 else { return false }
        if snap.mode.usesTeams {
            let t0 = snap.players.filter { $0.team == 0 }.count
            return t0 > 0 && t0 < snap.players.count
        }
        return true
    }

    // MARK: Lobby actions
    func startPractice() {
        notice = nil
        status = ""
        practice = true
        isHost = true
        myID = 0
        var s = MatchSnapshot()
        s.mode = .freeForAll
        s.map = selectedMap
        s.players = [PlayerInfo(id: 0, name: myPeer.displayName, team: 0)]
        snap = s
        inRoom = true
        matchStarted = true
    }

    func host() {
        notice = nil
        status = ""
        practice = false
        isHost = true
        myID = 0
        peerIDs = [:]
        nextID = 1
        var s = MatchSnapshot()
        s.mode = selectedMode
        s.map = selectedMap
        s.players = [PlayerInfo(id: 0, name: myPeer.displayName, team: 0)]
        snap = s
        inRoom = true
        startAdvertising()
    }

    func browse() {
        notice = nil
        isHost = false
        status = "Searching for nearby matches..."
        browser = MCNearbyServiceBrowser(peer: myPeer, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func invite(_ peer: MCPeerID) {
        isHost = false                       // whoever sends the invitation is always a player, never the host
        hostPeer = peer
        status = "Connecting to \(peer.displayName)..."
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    /// Leave the room or match (the host leaving ends it for everyone).
    func leaveMatch() {
        resetConnection()
        practice = false
    }

    // MARK: Room controls (host)
    func setMode(_ m: GameMode) {
        guard isHost, snap.phase == .waiting else { return }
        selectedMode = m
        snap.mode = m
        rebalanceTeams()
        broadcastSnapshot()
    }

    func setMap(_ i: Int) {
        guard isHost, snap.phase == .waiting else { return }
        selectedMap = i
        snap.map = i
        broadcastSnapshot()
    }

    /// Ask to move to another team (the host decides).
    func requestTeam(_ team: Int) {
        if isHost { applyTeam(id: myID, team: team) }
        else { send(.requestTeam(id: myID, team: team), reliable: true) }
    }

    // MARK: Bots (host)
    static let botNames = ["Bot Alpha", "Bot Bravo", "Bot Charlie", "Bot Delta", "Bot Echo", "Bot Foxtrot", "Bot Golf"]

    var botCount: Int { snap.players.filter { $0.isBot }.count }

    /// Set how many bots are in the room (real players always take priority).
    func setBotCount(_ n: Int) {
        guard isHost, !practice, snap.phase == .waiting else { return }
        let humans = snap.players.filter { !$0.isBot }
        let target = max(0, min(n, GameNetwork.maxPlayers - humans.count))
        var players = humans
        for i in 0..<target {
            let t0 = players.filter { $0.team == 0 }.count
            let team = t0 <= players.count - t0 ? 0 : 1
            players.append(PlayerInfo(id: 20 + i, name: GameNetwork.botNames[i % GameNetwork.botNames.count],
                                      team: team, kills: 0, deaths: 0, isBot: true))
        }
        snap.players = players
        broadcastSnapshot()
    }

    /// Fill every empty spot in the room with a bot.
    func fillWithBots() {
        setBotCount(GameNetwork.maxPlayers - snap.players.filter { !$0.isBot }.count)
    }

    func beginMatch() {
        guard isHost, snap.phase == .waiting, canStart else { return }
        stopDiscovery()                      // the room is locked while the match runs
        for i in snap.players.indices { snap.players[i].kills = 0; snap.players[i].deaths = 0 }
        snap.teamScore = [0, 0]
        snap.round = 1
        snap.winner = -1
        snap.phase = .countdown
        snap.countdown = 3
        broadcastSnapshot()
        matchStarted = true
    }

    /// After a match everyone goes back to the room, on the next map.
    func returnToRoom() {
        guard isHost, !practice, matchStarted else { return }
        snap.phase = .waiting
        snap.map = (snap.map + 1) % ArenaMap.all.count
        selectedMap = snap.map
        broadcastSnapshot()
        matchStarted = false
        if snap.players.count < GameNetwork.maxPlayers || botCount > 0 { startAdvertising() }
    }

    func broadcastSnapshot() {
        guard isHost else { return }
        send(.match(snap), reliable: true)
    }

    // MARK: Sending
    func send(_ message: NetMessage, reliable: Bool) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        let targets: [MCPeerID]
        if isHost {
            targets = session.connectedPeers
        } else if let h = hostPeer, let live = session.connectedPeers.first(where: { $0 == h || $0.displayName == h.displayName }) {
            targets = [live]                 // players only ever talk to the host
        } else {
            return
        }
        guard !targets.isEmpty else { return }
        try? session.send(data, toPeers: targets, with: reliable ? .reliable : .unreliable)
    }

    private func send(_ message: NetMessage, to peer: MCPeerID, reliable: Bool) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: [peer], with: reliable ? .reliable : .unreliable)
    }

    private func forward(_ data: Data, except peer: MCPeerID, reliable: Bool) {
        let targets = session.connectedPeers.filter { $0 != peer && $0.displayName != peer.displayName }
        guard !targets.isEmpty else { return }
        try? session.send(data, toPeers: targets, with: reliable ? .reliable : .unreliable)
    }

    // MARK: Internals
    private func startAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = MCNearbyServiceAdvertiser(peer: myPeer, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    private func stopDiscovery() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        foundPeers = []
    }

    private func resetConnection() {
        stopDiscovery()
        isHost = false
        inRoom = false
        matchStarted = false
        hostPeer = nil
        peerIDs = [:]
        nextID = 1
        status = ""
        myID = 0
        snap = MatchSnapshot()
        session.disconnect()
    }

    private func rebalanceTeams() {
        let order = snap.players.indices.sorted { snap.players[$0].id < snap.players[$1].id }
        for (n, i) in order.enumerated() { snap.players[i].team = n % 2 }
    }

    private func applyTeam(id: Int, team: Int) {
        guard snap.phase == .waiting, snap.mode.usesTeams, (0...1).contains(team),
              let i = snap.players.firstIndex(where: { $0.id == id }),
              snap.players[i].team != team else { return }
        let targetCount = snap.players.filter { $0.team == team }.count
        let otherCount = snap.players.count - targetCount - 1
        guard targetCount < 4, targetCount <= otherCount else { return }   // keep the teams fair
        snap.players[i].team = team
        broadcastSnapshot()
    }

    private func uniqueName(_ base: String) -> String {
        var name = base
        var n = 2
        while snap.players.contains(where: { $0.name == name }) {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }

    private func lookup(_ peer: MCPeerID) -> (key: MCPeerID, id: Int)? {
        for (k, v) in peerIDs where k == peer || k.displayName == peer.displayName { return (k, v) }
        return nil
    }

    private func hostPeerChanged(_ peer: MCPeerID, _ state: MCSessionState) {
        switch state {
        case .connected:
            guard lookup(peer) == nil, snap.phase == .waiting else { return }
            if snap.players.count >= GameNetwork.maxPlayers {                // the room is full: a bot steps aside
                guard let bi = snap.players.lastIndex(where: { $0.isBot }) else { return }
                snap.players.remove(at: bi)
            }
            let id = nextID
            nextID += 1
            peerIDs[peer] = id
            let t0 = snap.players.filter { $0.team == 0 }.count
            let t1 = snap.players.count - t0
            snap.players.append(PlayerInfo(id: id, name: uniqueName(peer.displayName), team: t0 <= t1 ? 0 : 1))
            send(.welcome(id: id), to: peer, reliable: true)
            broadcastSnapshot()
        case .notConnected:
            if let found = lookup(peer) {
                peerIDs.removeValue(forKey: found.key)
                snap.players.removeAll { $0.id == found.id }
                broadcastSnapshot()
                onPlayerLeft?(found.id)
            }
        default:
            break
        }
    }

    private func playerPeerChanged(_ peer: MCPeerID, _ state: MCSessionState) {
        guard let hp = hostPeer, peer == hp || peer.displayName == hp.displayName else { return }
        switch state {
        case .connected:
            inRoom = true
            status = ""
            notice = nil
            browser?.stopBrowsingForPeers()
            browser = nil
            foundPeers = []
        case .notConnected:
            if inRoom {
                resetConnection()
                notice = "The host left the match."
            } else {
                status = ""
                notice = "Couldn't join that match."
            }
        default:
            break
        }
    }

    private func handleIncoming(_ msg: NetMessage, raw: Data, from peer: MCPeerID) {
        switch msg {
        case .match(let s):                          // from the host
            snap = s
            if s.phase == .waiting { matchStarted = false }
            else if !matchStarted { matchStarted = true }
            onMessage?(msg)
        case .welcome(let id):
            myID = id
        case .requestTeam(let id, let team):
            if isHost { applyTeam(id: id, team: team) }
        case .state:
            if isHost { forward(raw, except: peer, reliable: false) }
            onMessage?(msg)
        case .shot, .hit:
            if isHost { forward(raw, except: peer, reliable: true) }
            onMessage?(msg)
        case .died, .killed:
            onMessage?(msg)
        }
    }
}

extension GameNetwork: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            if self.practice { return }
            if self.isHost { self.hostPeerChanged(peerID, state) }
            else { self.playerPeerChanged(peerID, state) }
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
        DispatchQueue.main.async { self.handleIncoming(msg, raw: data, from: peerID) }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}

extension GameNetwork: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            let ok = self.isHost && self.inRoom && self.snap.phase == .waiting
                && (self.snap.players.count < GameNetwork.maxPlayers || self.snap.players.contains(where: { $0.isBot }))
            invitationHandler(ok, ok ? self.session : nil)
        }
    }
}

extension GameNetwork: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { if !self.foundPeers.contains(peerID) { self.foundPeers.append(peerID) } }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.foundPeers.removeAll { $0 == peerID } }
    }
}
