import SwiftUI

final class SoloGame: ObservableObject {
    static let totalWords = 10
    static let fullSeconds = 3.0     // full points for the first 3 seconds
    static let drainSeconds = 27.0   // then drains to the floor over 27 seconds
    static let floorFraction = 0.2
    static let capSeconds = 60.0     // a word is skipped automatically after this

    struct Entry: Identifiable {
        let id = UUID()
        let word: String
        let seconds: Double?
        let points: Int
    }

    enum Phase { case countdown, playing, between, over }

    let board = BoardModel()
    @Published private(set) var phase: Phase = .countdown
    @Published private(set) var index = 0
    @Published private(set) var score = 0
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var message: BoardMessage?
    @Published private(set) var log: [Entry] = []
    @Published private(set) var newBest = false

    private(set) var word = ""
    private var start = Date()
    private var deck = WordDeck()
    private let scheduler = Scheduler()

    init() {
        board.onFull = { [weak self] guess in self?.guess(guess) }
    }

    static func points(for word: String, seconds: Double) -> Int {
        let f = seconds <= fullSeconds
            ? 1
            : max(floorFraction, 1 - (1 - floorFraction) * (seconds - fullSeconds) / drainSeconds)
        return Int((Double(word.count * 100) * f / 5).rounded()) * 5
    }

    var available: Int { phase == .playing ? Self.points(for: word, seconds: elapsed) : 0 }
    var availableFraction: Double {
        word.isEmpty || phase == .countdown ? 1 : Double(available) / Double(word.count * 100)
    }

    func begin() {
        scheduler.cancelAll()
        index = 0; score = 0; log = []; newBest = false; elapsed = 0; word = ""
        phase = .countdown
        board.blank(6)
        runCountdown(scheduler, say: { [weak self] in self?.message = $0 }) { [weak self] in
            self?.next()
        }
    }

    func stop() { scheduler.cancelAll() }

    func tick() {
        guard phase == .playing else { return }
        elapsed = Date().timeIntervalSince(start)
        if elapsed >= Self.capSeconds { skip(timedOut: true) }
    }

    func skip(timedOut: Bool = false) {
        guard phase == .playing else { return }
        phase = .between
        log.append(Entry(word: word, seconds: nil, points: 0))
        board.show(word, style: .lose)
        Feedback.lose()
        message = BoardMessage(title: timedOut ? "Out of time" : "Skipped", subtitle: "No points")
        scheduler.after(1.6) { [weak self] in self?.next() }
    }

    private func next() {
        guard index < Self.totalWords else { finish(); return }
        index += 1
        word = deck.next()
        board.load(WordBank.scramble(word))
        board.locked = false
        message = nil
        start = Date()
        elapsed = 0
        phase = .playing
    }

    private func guess(_ guess: String) {
        guard phase == .playing else { return }
        guard WordBank.isCorrect(guess, answer: word) else { board.reject(); return }
        let seconds = Date().timeIntervalSince(start)
        let pts = Self.points(for: word, seconds: seconds)
        score += pts
        log.append(Entry(word: guess, seconds: seconds, points: pts))
        phase = .between
        board.show(guess, style: .win)
        Feedback.win()
        message = BoardMessage(title: "+\(pts)", subtitle: String(format: "%.1f seconds", seconds), good: true)
        scheduler.after(1.3) { [weak self] in self?.next() }
    }

    private func finish() {
        phase = .over
        let best = UserDefaults.standard.integer(forKey: "best")
        if score > best {
            UserDefaults.standard.set(score, forKey: "best")
            newBest = score > 0
        }
        Feedback.fanfare()
    }
}

struct SoloView: View {
    let exit: () -> Void
    @StateObject private var game = SoloGame()
    @AppStorage("best") private var best = 0
    private let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let color = Theme.players[1]

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 18) {
                HStack {
                    Button("Menu") { game.stop(); exit() }.buttonStyle(PillButtonStyle())
                    Spacer()
                    (Text("Best: ").foregroundColor(Theme.muted) + Text(best > 0 ? best.formatted() : "—"))
                        .font(Theme.body(14, weight: .bold))
                }
                HStack(spacing: 8) {
                    StatBox(label: "Word", value: "\(max(game.index, 1))/\(SoloGame.totalWords)")
                    StatBox(label: "Score", value: game.score.formatted())
                    StatBox(label: "Time", value: String(format: "%.1fs", game.elapsed))
                }

                if game.phase == .over {
                    SoloResults(game: game, again: { game.begin() }, menu: exit)
                } else {
                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        Text(game.phase == .playing ? "\(game.available)" : "—")
                            .font(Theme.display(56))
                            .monospacedDigit()
                            .foregroundStyle(color)
                        Text("POINTS UP FOR GRABS")
                            .font(Theme.body(12, weight: .heavy))
                            .foregroundStyle(Theme.muted)
                        FillBar(fraction: game.availableFraction, color: color)
                            .frame(maxWidth: 300)
                    }
                    BoardView(model: game.board, color: color, width: geo.size.width - 32, maxTile: 64, message: game.message)
                    HStack(spacing: 10) {
                        Button("Clear") { game.board.clear() }
                        Button("Skip") { game.skip() }
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(game.phase != .playing)
                    .opacity(game.phase == .playing ? 1 : 0.35)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onAppear { game.begin() }
        .onDisappear { game.stop() }
        .onReceive(ticker) { _ in game.tick() }
    }
}

struct SoloResults: View {
    @ObservedObject var game: SoloGame
    let again: () -> Void
    let menu: () -> Void

    var body: some View {
        let solved = game.log.compactMap { $0.seconds }
        ScrollView {
            VStack(spacing: 18) {
                Text("Final score").font(Theme.display(22)).foregroundStyle(Theme.muted)
                Text(game.score.formatted())
                    .font(Theme.display(84))
                    .monospacedDigit()
                    .foregroundStyle(Theme.players[1])
                if game.newBest {
                    Text("New best!").font(Theme.display(22)).foregroundStyle(Theme.players[0])
                }
                HStack(spacing: 8) {
                    StatBox(label: "Solved", value: "\(solved.count)/\(SoloGame.totalWords)")
                    StatBox(label: "Avg time", value: solved.isEmpty ? "—" : String(format: "%.1fs", solved.reduce(0, +) / Double(solved.count)))
                    StatBox(label: "Fastest", value: solved.min().map { String(format: "%.1fs", $0) } ?? "—")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], spacing: 6) {
                    ForEach(game.log) { entry in
                        Text(entry.seconds == nil ? entry.word.uppercased() : "\(entry.word.uppercased()) +\(entry.points)")
                            .font(Theme.body(13, weight: .heavy))
                            .strikethrough(entry.seconds == nil)
                            .foregroundStyle(entry.seconds == nil ? Theme.muted : Theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.feltHi))
                    }
                }
                HStack(spacing: 12) {
                    Button("Play again", action: again).buttonStyle(ChunkyButtonStyle(color: Theme.players[1]))
                    Button("Menu", action: menu).buttonStyle(ChunkyButtonStyle(color: Theme.feltLo, foreground: Theme.text))
                }
            }
            .padding(.top, 12)
        }
    }
}
