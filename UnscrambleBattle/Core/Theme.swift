import SwiftUI

enum Theme {
    static let felt = Color(hex: 0x2B1F44)
    static let feltHi = Color(hex: 0x3B2B5E)
    static let feltLo = Color(hex: 0x1D1530)
    static let tile = Color(hex: 0xF7EFDC)
    static let tileEdge = Color(hex: 0xC9B896)
    static let tileInk = Color(hex: 0x2B1F44)
    static let text = Color(hex: 0xF4EEFC)
    static let muted = Color(hex: 0xB3A5D4)
    static let bad = Color(hex: 0xFF5D73)

    /// One color per seat: orange, teal, yellow, pink, periwinkle, lime.
    static let players: [Color] = ([0xFF8F3F, 0x46D3C1, 0xFFD23F, 0xFF6FB5, 0x8FA8FF, 0x9BE15D] as [UInt32]).map { Color(hex: $0) }

    static func player(_ index: Int) -> Color {
        players[((index % players.count) + players.count) % players.count]
    }

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Buttons

struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Theme.players[0]
    var foreground: Color = Theme.feltLo
    var size: CGFloat = 22
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return configuration.label
            .font(Theme.display(size))
            .foregroundStyle(foreground)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(shape.fill(color))
            .background(
                shape.fill(color)
                    .overlay(shape.fill(Color.black.opacity(0.4)))
                    .offset(y: pressed ? 1 : 5)
            )
            .offset(y: pressed ? 4 : 0)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(14, weight: .heavy))
            .textCase(.uppercase)
            .foregroundStyle(configuration.isPressed ? Theme.text : Theme.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.feltLo.opacity(configuration.isPressed ? 1 : 0.8)))
    }
}

// MARK: - Small shared pieces

struct FillBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.feltHi)
                Capsule()
                    .fill(color)
                    .frame(width: g.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 8)
    }
}

struct StatBox: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Theme.body(11, weight: .heavy))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(Theme.display(24))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.feltHi))
    }
}

struct CountStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(Theme.body(12, weight: .heavy))
                .foregroundStyle(Theme.muted)
                .padding(.trailing, 4)
            stepButton("−", label: "Fewer") { value = max(range.lowerBound, value - 1) }
            Text("\(value)")
                .font(Theme.display(26))
                .monospacedDigit()
                .frame(minWidth: 34)
            stepButton("+", label: "More") { value = min(range.upperBound, value + 1) }
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 22, weight: .black))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.feltLo))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .accessibilityLabel(label)
    }
}

struct TopBar: View {
    let title: String
    var backLabel = "Back"
    let back: () -> Void

    var body: some View {
        HStack {
            Button(backLabel, action: back).buttonStyle(PillButtonStyle())
            Spacer()
            Text(title).font(Theme.display(22))
        }
    }
}

/// The 5-3-2-1 placement points, shown as little chips.
struct PointsTable: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                HStack(spacing: 4) {
                    Text(ordinal(i + 1)).foregroundStyle(Theme.muted)
                    Text("\(PartyController.points(forPlace: i))")
                }
                .font(Theme.body(13, weight: .heavy))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.feltHi))
            }
        }
    }
}
