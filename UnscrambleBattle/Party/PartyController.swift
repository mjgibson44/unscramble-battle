import Foundation
import MultipeerConnectivity

/// A player in a Party game. `color` is a seat index into `Theme.players`.
struct PartyPlayer: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var color: Int
    var score: Int = 0
}

/// Everything the phones say to each other. The host is in charge: it deals words,
/// decides finishing order, and keeps the scores.
enum PartyMessage: Codable {
    case hello(id: String, name: String)                                   // guest -> host
    case lobby(players: [PartyPlayer], rounds: Int)                        // host -> all
    case round(number: Int, total: Int, scrambled: String, answer: String) // host -> all
    case solved(id: String, round: Int)                                    // guest -> host
    case progress(round: Int, finishers: [String])                         // host -> all
    case roundOver(round: Int, answer: String, finishers: [String], players: [PartyPlayer])
    case gameOver(players: [PartyPlayer])
    case refused(reason: String)                                           // host -> one guest
}

struct Standing: Identifiable {
    let rank: Int
    let player: PartyPlayer
    var id: String { player.id }
}

struct NearbyGame: Identifiable {
    let peer: MCPeerID
    let hostName: String
    var id: ObjectIdentifier { ObjectIdentifier(peer) }
}

final class PartyController: NSObject, ObservableObject {
    enum Role { case none, host, guest }
    enum Phase: Equatable { case setup, browsing, lobby, countdown, playing, roundOver, gameOver, ended(String) }

    static let serviceType = "unscramble"   // must match NSBonjourServices in Info.plist
    static let maxPlayers = 6
    static let placePoints = [5, 3, 2, 1]
    static let roundSeconds = 45.0
    static let countdownSeconds = 2.25

    static func points(forPlace index: Int) -> Int {
        index < placePoints.count ? placePoints[index] : 0
    }

    @Published private(set) var role: Role = .none
    @Published private(set) var phase: Phase = .setup
    @Published private(set) var players: [PartyPlayer] = []
    @Published private(set) var nearby: [NearbyGame] = []
    @Published private(set) var joining: MCPeerID?
    @Published private(set) var joinError: String?
    @Published private(set) var roundNumber = 0
    @Published private(set) var totalRounds = 10
    @Published private(set) var finishers: [String] = []
    @Published private(set) var answer = ""
    @Published private(set) var timeLeft: Double = 1
    @Published private(set) var message: BoardMessage?
    @Published var rounds: Int = (UserDefaults.standard.object(forKey: "partyRounds") as? Int) ?? 10 {
        didSet {
            UserDefaults.standard.set(rounds, forKey: "partyRounds")
            if role == .host && phase == .lobby { broadcastLobby() }
        }
    }

    let board = BoardModel()
    let myId = UUID().uuidString
    private(set) var myName = ""

    private var peerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var hostPeer: MCPeerID?
    private var peerPlayers: [MCPeerID: String] = [:]   // host only: who is who
    private var deck = WordDeck()
    private let scheduler = Scheduler()
    private var roundStart = Date()
    private var roundOpen = false   // host only: still accepting finishes
    private var iSolved = false
    private var timedOut = false

    override init() {
        super.init()
        board.onFull = { [weak self] guess in self?.localGuess(guess) }
    }

    var isHost: Bool { role == .host }
    var hostId: String? { players.first?.id }   // the host always sits in seat 0
    var canStart: Bool { isHost && phase == .lobby && players.count >= 2 }
    var me: PartyPlayer? { players.first { $0.id == myId } }

    /// Highest score first; players with equal scores share a rank.
    var standings: [Standing] {
        let sorted = players.sorted { $0.score != $1.score ? $0.score > $1.score : $0.color < $1.color }
        return sorted.map { p in Standing(rank: sorted.filter { $0.score > p.score }.count + 1, player: p) }
    }

    // MARK: - Setup

    func host(name: String) {
        leave()
        myName = Self.clean(name)
        role = .host
        makeSession()
        players = [PartyPlayer(id: myId, name: myName, color: 0)]
        startAdvertising()
        phase = .lobby
    }

    func browse(name: String) {
        leave()
        myName = Self.clean(name)
        role = .guest
        makeSession()
        guard let peerID = peerID else { return }
        let b = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b
        phase = .browsing
    }

    func join(_ game: NearbyGame) {
        guard let session = session, let browser = browser, joining == nil else { return }
        joinError = nil
        joining = game.peer
        browser.invitePeer(game.peer, to: session, withContext: nil, timeout: 15)
    }

    func leave() {
        scheduler.cancelAll()
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session?.delegate = nil
        session?.disconnect(); session = nil
        peerID = nil; hostPeer = nil; joining = nil; joinError = nil
        peerPlayers = [:]
        players = []; nearby = []; finishers = []
        message = nil; roundOpen = false; roundNumber = 0
        role = .none
        phase = .setup
        board.blank(6)
    }

    private func end(_ reason: String) {
        leave()
        phase = .ended(reason)
    }

    private static func clean(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Player" : String(trimmed.prefix(16))
    }

    private func makeSession() {
        let peer = MCPeerID(displayName: String(myName.prefix(20)))
        peerID = peer
        let s = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
    }

    private func startAdvertising() {
        guard let peerID = peerID else { return }
        advertiser?.stopAdvertisingPeer()
        let a = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["name": myName], serviceType: Self.serviceType)
        a.delegate = self
        a.startAdvertisingPeer()
        advertiser = a
    }

    private func send(_ msg: PartyMessage, to peers: [MCPeerID]? = nil) {
        guard let session = session else { return }
        let targets = peers ?? session.connectedPeers
        guard !targets.isEmpty, let data = try? JSONEncoder().encode(msg) else { return }
        try? session.send(data, toPeers: targets, with: .reliable)
    }

    // MARK: - Host

    private func broadcastLobby() {
        send(.lobby(players: players, rounds: rounds))
    }

    func startGame() {
        guard canStart else { return }
        for i in players.indices { players[i].score = 0 }
        roundNumber = 0
        totalRounds = rounds
        advertiser?.stopAdvertisingPeer()   // nobody new can find the game once it starts
        hostNextRound()
    }

    func backToLobby() {
        guard isHost else { return }
        scheduler.cancelAll()
        for i in players.indices { players[i].score = 0 }
        roundNumber = 0; finishers = []; message = nil; roundOpen = false
        board.blank(6)
        phase = .lobby
        startAdvertising()
        broadcastLobby()
    }

    private func hostNextRound() {
        let word = deck.next()
        let scrambled = WordBank.scramble(word)
        let n = roundNumber + 1
        send(.round(number: n, total: totalRounds, scrambled: scrambled, answer: word))
        beginRound(number: n, total: totalRounds, scrambled: scrambled, answer: word)
        roundOpen = true
        // A little grace past the clock so late messages from guests still count.
        scheduler.after(Self.countdownSeconds + Self.roundSeconds + 0.75) { [weak self] in
            guard let self = self, self.roundNumber == n else { return }
            self.hostEndRound()
        }
    }

    private var everyoneFinished: Bool {
        players.allSatisfy { finishers.contains($0.id) }
    }

    private func hostRecordFinish(_ id: String) {
        guard roundOpen, !finishers.contains(id), let idx = players.firstIndex(where: { $0.id == id }) else { return }
        players[idx].score += Self.points(forPlace: finishers.count)
        finishers.append(id)
        send(.progress(round: roundNumber, finishers: finishers))
        updateWaitingMessage()
        if everyoneFinished {
            let n = roundNumber
            scheduler.after(0.8) { [weak self] in
                guard let self = self, self.roundNumber == n else { return }
                self.hostEndRound()
            }
        }
    }

    private func hostEndRound() {
        guard roundOpen else { return }
        roundOpen = false
        send(.roundOver(round: roundNumber, answer: answer, finishers: finishers, players: players))
        showRoundOver(answer: answer, finishers: finishers, players: players)
        let n = roundNumber
        scheduler.after(4) { [weak self] in
            guard let self = self, self.isHost, self.roundNumber == n else { return }
            if n >= self.totalRounds {
                self.send(.gameOver(players: self.players))
                self.showGameOver(self.players)
            } else {
                self.hostNextRound()
            }
        }
    }

    // MARK: - Everyone

    private func beginRound(number: Int, total: Int, scrambled: String, answer: String) {
        roundNumber = number
        totalRounds = total
        self.answer = answer
        finishers = []
        iSolved = false
        timedOut = false
        timeLeft = 1
        phase = .countdown
        board.blank(scrambled.count)
        runCountdown(scheduler, say: { [weak self] m in self?.message = m }) { [weak self] in
            guard let self = self, self.roundNumber == number, self.phase == .countdown else { return }
            self.board.load(scrambled)
            self.board.locked = false
            self.message = nil
            self.roundStart = Date()
            self.phase = .playing
        }
    }

    func tick() {
        guard phase == .playing else { return }
        let left = Self.roundSeconds - Date().timeIntervalSince(roundStart)
        timeLeft = max(0, left / Self.roundSeconds)
        if left <= 0 && !iSolved && !timedOut {
            timedOut = true
            board.show(answer, style: .lose)
            message = BoardMessage(title: "Time's up", subtitle: "Waiting for the round to end")
        }
    }

    private func localGuess(_ guess: String) {
        guard phase == .playing, !iSolved, !timedOut else { return }
        guard WordBank.isCorrect(guess, answer: answer) else { board.reject(); return }
        iSolved = true
        board.show(guess, style: .win)
        Feedback.win()
        message = BoardMessage(title: "Solved!", subtitle: "Waiting for the others", good: true)
        if isHost {
            hostRecordFinish(myId)
        } else if let hostPeer = hostPeer {
            send(.solved(id: myId, round: roundNumber), to: [hostPeer])
        }
    }

    private func updateWaitingMessage() {
        guard iSolved, phase == .playing, let place = finishers.firstIndex(of: myId) else { return }
        let pts = Self.points(forPlace: place)
        message = BoardMessage(
            title: "\(ordinal(place + 1)) place!",
            subtitle: pts > 0 ? "+\(pts) points · waiting for the others" : "Waiting for the others",
            good: true
        )
    }

    private func showRoundOver(answer: String, finishers: [String], players: [PartyPlayer]) {
        self.finishers = finishers
        self.players = players
        phase = .roundOver
        if let place = finishers.firstIndex(of: myId) {
            let pts = Self.points(forPlace: place)
            message = BoardMessage(
                title: "\(ordinal(place + 1)) place",
                subtitle: pts > 0 ? "+\(pts) points" : "No points this time",
                good: true
            )
        } else {
            board.show(answer, style: .lose)
            Feedback.lose()
            message = BoardMessage(title: "Round over", subtitle: "The word was \(answer.uppercased())")
        }
    }

    private func showGameOver(_ players: [PartyPlayer]) {
        self.players = players
        phase = .gameOver
        Feedback.fanfare()
    }

    // MARK: - Incoming

    fileprivate func handle(_ msg: PartyMessage, from peer: MCPeerID) {
        switch msg {
        case let .hello(id, name):
            guard isHost else { return }
            if phase != .lobby {
                send(.refused(reason: "That game has already started."), to: [peer])
                return
            }
            if let i = players.firstIndex(where: { $0.id == id }) {
                players[i].name = name
            } else {
                guard players.count < Self.maxPlayers else {
                    send(.refused(reason: "That game is full. It already has 6 players."), to: [peer])
                    return
                }
                let taken = Set(players.map { $0.color })
                let seat = (0..<Self.maxPlayers).first { !taken.contains($0) } ?? 0
                players.append(PartyPlayer(id: id, name: name, color: seat))
            }
            peerPlayers[peer] = id
            broadcastLobby()

        case let .solved(id, round):
            guard isHost, round == roundNumber, peerPlayers[peer] == id else { return }
            hostRecordFinish(id)

        case let .lobby(players, rounds):
            guard role == .guest else { return }
            if phase != .lobby && phase != .browsing {
                scheduler.cancelAll()
                board.blank(6)
                message = nil
            }
            self.players = players
            totalRounds = rounds
            joining = nil
            phase = .lobby

        case let .round(number, total, scrambled, answer):
            guard role == .guest else { return }
            beginRound(number: number, total: total, scrambled: scrambled, answer: answer)

        case let .progress(round, finishers):
            guard role == .guest, round == roundNumber else { return }
            self.finishers = finishers
            updateWaitingMessage()

        case let .roundOver(round, answer, finishers, players):
            guard role == .guest, round == roundNumber else { return }
            showRoundOver(answer: answer, finishers: finishers, players: players)

        case let .gameOver(players):
            guard role == .guest else { return }
            showGameOver(players)

        case let .refused(reason):
            guard role == .guest else { return }
            end(reason)
        }
    }

    fileprivate func peerChanged(_ peer: MCPeerID, to state: MCSessionState) {
        switch state {
        case .connected:
            if role == .guest, peer == joining {
                hostPeer = peer
                browser?.stopBrowsingForPeers()
                send(.hello(id: myId, name: myName), to: [peer])
            }
        case .notConnected:
            if role == .guest {
                if peer == hostPeer {
                    end("The host left the game.")
                } else if peer == joining {
                    joining = nil
                    joinError = "Couldn't join. Check that the host is still in the lobby and try again."
                }
            } else if isHost, let id = peerPlayers.removeValue(forKey: peer) {
                players.removeAll { $0.id == id }
                switch phase {
                case .lobby:
                    broadcastLobby()
                case .gameOver:
                    break
                default:
                    if players.count < 2 {
                        scheduler.cancelAll()
                        roundOpen = false
                        send(.gameOver(players: players))
                        showGameOver(players)
                    } else if roundOpen && everyoneFinished {
                        hostEndRound()
                    }
                }
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    fileprivate func owns(_ s: MCSession) -> Bool { session === s }
    fileprivate func owns(_ b: MCNearbyServiceBrowser) -> Bool { browser === b }

    fileprivate func found(_ peer: MCPeerID, name: String) {
        guard !nearby.contains(where: { $0.peer == peer }) else { return }
        nearby.append(NearbyGame(peer: peer, hostName: name))
    }

    fileprivate func lost(_ peer: MCPeerID) {
        nearby.removeAll { $0.peer == peer }
    }

    fileprivate func shouldAccept() -> MCSession? {
        guard isHost, phase == .lobby, players.count < Self.maxPlayers else { return nil }
        return session
    }

    fileprivate func networkFailed() {
        end("Couldn't connect to nearby phones. Turn on Wi-Fi and Bluetooth, and allow Local Network access for Unscramble Battle in Settings.")
    }
}

// MARK: - MultipeerConnectivity delegates (called off the main thread)

extension PartyController: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.owns(session) else { return }
            self.peerChanged(peerID, to: state)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = try? JSONDecoder().decode(PartyMessage.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.owns(session) else { return }
            self.handle(msg, from: peerID)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension PartyController: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            if let session = self?.shouldAccept() {
                invitationHandler(true, session)
            } else {
                invitationHandler(false, nil)
            }
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in self?.networkFailed() }
    }
}

extension PartyController: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let name = info?["name"] ?? peerID.displayName
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.owns(browser) else { return }
            self.found(peerID, name: name)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.owns(browser) else { return }
            self.lost(peerID)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { [weak self] in self?.networkFailed() }
    }
}
