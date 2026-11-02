import SwiftUI

enum RevealStyle {
    case win, lose
}

struct Reveal: Equatable {
    var word: [Character]
    var style: RevealStyle
}

/// Text shown in place of the letter rack (countdown numbers, results, etc.).
struct BoardMessage: Equatable {
    var title: String
    var subtitle: String? = nil
    var big = false
    var good = false
}

/// One player's scrambled letters and the slots they tap them into.
final class BoardModel: ObservableObject {
    @Published private(set) var letters: [Character] = []
    @Published private(set) var picks: [Int] = []
    @Published private(set) var reveal: Reveal?
    @Published private(set) var isBlank = true
    @Published private(set) var wrongFlash = false
    @Published var locked = true

    /// Called when every slot is filled, with the spelled word in lowercase.
    var onFull: ((String) -> Void)?
    private var epoch = 0

    var count: Int { reveal?.word.count ?? letters.count }

    func load(_ scrambled: String) {
        epoch += 1
        letters = Array(scrambled.uppercased())
        picks = []
        reveal = nil
        isBlank = false
        wrongFlash = false
    }

    func blank(_ n: Int) {
        epoch += 1
        letters = Array(repeating: " ", count: n)
        picks = []
        reveal = nil
        isBlank = true
        wrongFlash = false
        locked = true
    }

    func pick(_ i: Int) {
        guard !locked, !isBlank, i < letters.count, !picks.contains(i), picks.count < letters.count else { return }
        picks.append(i)
        Feedback.tap()
        if picks.count == letters.count {
            onFull?(String(picks.map { letters[$0] }).lowercased())
        }
    }

    func unpick(at k: Int) {
        guard !locked, k < picks.count else { return }
        picks.remove(at: k)
        Feedback.undo()
    }

    func clear() {
        guard !locked, !picks.isEmpty else { return }
        picks = []
        Feedback.undo()
    }

    /// Wrong answer: flash red, shake, then empty the slots.
    func reject() {
        locked = true
        wrongFlash = true
        Feedback.wrong()
        let e = epoch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.epoch == e else { return }
            self.wrongFlash = false
            self.picks = []
            self.locked = false
        }
    }

    func show(_ word: String, style: RevealStyle) {
        epoch += 1
        locked = true
        wrongFlash = false
        reveal = Reveal(word: Array(word.uppercased()), style: style)
    }
}

// MARK: - Views

enum TileKind {
    case rack, used, empty, filled, wrong, win, lose
}

struct TileFace: View {
    let letter: Character?
    let kind: TileKind
    let size: CGFloat
    let color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
        return ZStack {
            if hasEdge {
                shape.fill(Theme.tileEdge).offset(y: size * 0.08)
            }
            shape.fill(fill)
            if kind == .empty {
                shape.strokeBorder(color.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            if kind == .filled {
                shape.strokeBorder(color, lineWidth: 2)
            }
            if kind == .lose {
                shape.strokeBorder(Theme.muted.opacity(0.6), lineWidth: 2)
            }
            if let letter = letter {
                Text(String(letter))
                    .font(Theme.display(size * 0.56))
                    .foregroundStyle(ink)
            }
        }
        .frame(width: size, height: size)
        .opacity(kind == .used ? 0.12 : 1)
        .scaleEffect(kind == .used ? 0.9 : 1)
    }

    private var hasEdge: Bool { kind == .rack || kind == .filled }

    private var fill: Color {
        switch kind {
        case .rack, .filled, .used: return Theme.tile
        case .empty, .lose: return .clear
        case .wrong: return Theme.bad
        case .win: return color
        }
    }

    private var ink: Color {
        switch kind {
        case .wrong: return .white
        case .lose: return Theme.muted
        case .win: return Theme.feltLo
        default: return Theme.tileInk
        }
    }
}

struct BoardView: View {
    @ObservedObject var model: BoardModel
    let color: Color
    let width: CGFloat
    var maxTile: CGFloat = 62
    var message: BoardMessage? = nil

    private let gap: CGFloat = 6
    private var n: Int { max(model.count, 1) }
    private var size: CGFloat {
        max(22, min(maxTile, (width - gap * CGFloat(n - 1)) / CGFloat(n)))
    }

    var body: some View {
        VStack(spacing: size * 0.4) {
            slotRow
            ZStack {
                rackRow.opacity(message == nil && !model.isBlank ? 1 : 0)
                if let message = message {
                    MessageView(message: message, color: color)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(minHeight: size * 1.1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message)
        }
        .frame(width: max(width, 0))
    }

    private var slotRow: some View {
        HStack(spacing: gap) {
            ForEach(0..<n, id: \.self) { k in
                TileFace(letter: slotLetter(k), kind: slotKind(k), size: size, color: color)
                    .onTouchDown { model.unpick(at: k) }
            }
        }
        .modifier(Shake(amount: model.wrongFlash ? 1 : 0))
        .animation(.linear(duration: 0.4), value: model.wrongFlash)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: model.picks)
    }

    private var rackRow: some View {
        HStack(spacing: gap) {
            ForEach(Array(model.letters.indices), id: \.self) { i in
                TileFace(
                    letter: model.isBlank ? nil : model.letters[i],
                    kind: model.picks.contains(i) ? .used : .rack,
                    size: size,
                    color: color
                )
                .onTouchDown { model.pick(i) }
                .accessibilityLabel(String(model.letters[i]))
                .accessibilityAddTraits(.isButton)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.picks)
    }

    private func slotLetter(_ k: Int) -> Character? {
        if let r = model.reveal { return k < r.word.count ? r.word[k] : nil }
        return k < model.picks.count ? model.letters[model.picks[k]] : nil
    }

    private func slotKind(_ k: Int) -> TileKind {
        if let r = model.reveal { return r.style == .win ? .win : .lose }
        if k < model.picks.count { return model.wrongFlash ? .wrong : .filled }
        return .empty
    }
}

struct MessageView: View {
    let message: BoardMessage
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(message.title)
                .font(Theme.display(message.big ? 84 : 30))
                .foregroundStyle(message.big || message.good ? color : Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            if let subtitle = message.subtitle {
                Text(subtitle)
                    .font(Theme.body(15, weight: .heavy))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .id(message.title)
    }
}

struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}

/// Fires on finger-down instead of finger-up, so tapping fast feels instant.
struct TouchDownModifier: ViewModifier {
    let action: () -> Void
    @State private var isDown = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isDown {
                            isDown = true
                            action()
                        }
                    }
                    .onEnded { _ in isDown = false }
            )
    }
}

extension View {
    func onTouchDown(_ action: @escaping () -> Void) -> some View {
        modifier(TouchDownModifier(action: action))
    }
}
