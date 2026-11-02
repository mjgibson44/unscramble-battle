import SwiftUI

/// Two players on one phone. The top half is upside down so players can sit across from each other.
final class FaceOffGame: ObservableObject {
    static let roundSeconds = 45.0

    let boards = [BoardModel(), BoardModel()]
    @Published private(set) var scores = [0, 0]
    @Published private(set) var messages: [BoardMessage?] = [nil, nil]
    @Published private(set) var round = 0
    @Published private(set) var timeLeft: Double = 1
    @Published private(set) var over = false
    @Published private(set) var flash: Int?
    private(set) var target = 10

    private var word = ""
    private var start = Date()
    private var playing = false
    private var lastTick = 0
    private var deck = WordDeck()
    private let scheduler = Scheduler()

    init() {
        for p in 0..<2 {
            boards[p].onFull = { [weak self] guess in self?.guess(p, guess) }
        }
    }

    func begin(target: Int) {
        scheduler.cancelAll()
        self.target = target
        scores = [0, 0]; round = 0; over = false; playing = false; timeLeft = 1; flash = nil
        boards.forEach { $0.blank(6) }
        runCountdown(scheduler, say: { [weak self] m in self?.messages = [m, m] }) { [weak self] in
            self?.nextRound()
        }
    }

    func stop() { scheduler.cancelAll(); playing = false }

    func tick() {
        guard playing else { return }
        let left = Self.roundSeconds - Date().timeIntervalSince(start)
        timeLeft = max(0, left / Self.roundSeconds)
        let secs = Int(left.rounded(.up))
        if left < 5, secs > 0, secs != lastTick {
            lastTick = secs
            Feedback.tick()
        }
        if left <= 0 { timeout() }
    }

    private func nextRound() {
        round += 1
        word = deck.next()
        let scrambled = WordBank.scramble(word)
        boards.forEach { $0.load(scrambled); $0.locked = false }
        messages = [nil, nil]
        flash = nil
        start = Date()
        lastTick = 0
        playing = true
    }

    private func guess(_ p: Int, _ guess: String) {
        guard playing else { return }
        guard WordBank.isCorrect(guess, answer: word) else { boards[p].reject(); return }
        playing = false
        let o = 1 - p
        scores[p] += 1
        boards[p].show(guess, style: .win)
        boards[o].show(guess, style: .lose)
        flash = p

        if scores[p] >= target {
            over = true
            Feedback.fanfare()
            messages[p] = BoardMessage(title: "You win!", subtitle: "\(scores[p]) to \(scores[o])", good: true)
            messages[o] = BoardMessage(title: "So close!", subtitle: "\(scores[o]) to \(scores[p])")
            return
        }
        Feedback.win()
        let secs = Date().timeIntervalSince(start)
        messages[p] = BoardMessage(title: "+1 point!", subtitle: String(format: "%.1f seconds", secs), good: true)
        messages[o] = BoardMessage(title: "Player \(p + 1) got it", subtitle: "Get the next one")
        scheduler.after(2) { [weak self] in self?.nextRound() }
    }

    private func timeout() {
        playing = false
        Feedback.lose()
        boards.forEach { $0.show(word, style: .lose) }
        let m = BoardMessage(title: "Time's up", subtitle: "Nobody scores this round")
        messages = [m, m]
        scheduler.after(2.4) { [weak self] in self?.nextRound() }
    }
}

struct FaceOffView: View {
    let exit: () -> Void
    @AppStorage("faceOffTarget") private var target = 10
    @StateObject private var game = FaceOffGame()
    @State private var quitArmed = false
    private let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                half(1, width: geo.size.width)
                    .rotationEffect(.degrees(180))
                rail
                half(0, width: geo.size.width)
            }
        }
        .background(Theme.feltLo.ignoresSafeArea())
        .onAppear { game.begin(target: target) }
        .onDisappear { game.stop() }
        .onReceive(ticker) { _ in game.tick() }
    }

    private func half(_ p: Int, width: CGFloat) -> some View {
        let color = Theme.player(p)
        return VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Player \(p + 1)").font(Theme.display(20)).foregroundStyle(color)
                    Pips(count: game.target, filled: game.scores[p], color: color)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(game.scores[p])").font(Theme.display(46)).monospacedDigit()
                    Text("/\(game.target)").font(Theme.display(20)).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(color)
            }
            BoardView(model: game.boards[p], color: color, width: width - 32, maxTile: 56, message: game.messages[p])
            Button("Clear") { game.boards[p].clear() }
                .buttonStyle(PillButtonStyle())
                .opacity(game.boards[p].locked ? 0.35 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Theme.felt
                RadialGradient(
                    colors: [color.opacity(game.flash == p ? 0.45 : 0.16), .clear],
                    center: .bottom, startRadius: 0, endRadius: width * 0.9
                )
            }
            .animation(.easeOut(duration: 0.5), value: game.flash)
        )
    }

    private var rail: some View {
        HStack(spacing: 12) {
            if game.over {
                Spacer()
                Button("Rematch") { game.begin(target: target) }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.players[0], size: 17))
                Button("Menu", action: exit)
                    .buttonStyle(ChunkyButtonStyle(color: Theme.felt, foreground: Theme.text, size: 17))
                Spacer()
            } else {
                Button(quitArmed ? "Tap again" : "Quit") {
                    if quitArmed { game.stop(); exit() } else {
                        quitArmed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { quitArmed = false }
                    }
                }
                .buttonStyle(PillButtonStyle())
                FillBar(fraction: game.timeLeft, color: game.timeLeft < 0.22 ? Theme.bad : Theme.muted)
                Text("R\(max(game.round, 1))")
                    .font(Theme.display(16))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Theme.feltLo)
    }
}

struct Pips: View {
    let count: Int
    let filled: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(i < filled ? color : color.opacity(0.22))
                    .frame(width: 12, height: 12)
            }
        }
    }
}
