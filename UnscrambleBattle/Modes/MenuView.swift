import SwiftUI

struct MenuView: View {
    let go: (Screen) -> Void
    @AppStorage("best") private var best = 0
    @AppStorage("sound") private var sound = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Logo().padding(.top, 20)

                Text("Tap the letters in the right order. Five to nine letters, one word at a time.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                ModeCard(
                    title: "Party",
                    color: Theme.players[2],
                    blurb: "2 to 6 players, each on their own iPhone nearby. Everyone races the same word, and points go by finishing place."
                ) {
                    PointsTable()
                    Spacer()
                    Button("Play") { go(.party) }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.players[2]))
                }

                ModeCard(
                    title: "Solo Sprint",
                    color: Theme.players[1],
                    blurb: "Ten words against the clock. Each word starts at 100 points per letter and drains as you think."
                ) {
                    Text("Best: ").foregroundColor(Theme.muted)
                        + Text(best > 0 ? best.formatted() : "—").foregroundColor(Theme.text)
                    Spacer()
                    Button("Start") { go(.solo) }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.players[1]))
                }

                Button(sound ? "Sound: on" : "Sound: off") { sound.toggle() }
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.muted)
                    .padding(8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

struct ModeCard<Footer: View>: View {
    let title: String
    let color: Color
    let blurb: String
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.display(26))
                .foregroundStyle(color)
            Text(blurb)
                .font(Theme.body(15))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { footer() }
                VStack(alignment: .leading, spacing: 12) { footer() }
            }
            .font(Theme.body(14))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.feltHi))
        .overlay(shape.strokeBorder(color.opacity(0.4), lineWidth: 2))
    }
}

struct Logo: View {
    var body: some View {
        VStack(spacing: 8) {
            row("UNSCRAMBLE", colored: false)
            row("BATTLE", colored: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Unscramble Battle")
    }

    private func row(_ word: String, colored: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(word.enumerated()), id: \.offset) { i, ch in
                let fill = colored ? Theme.player(i % 2) : Theme.tile
                Text(String(ch))
                    .font(Theme.display(20))
                    .foregroundStyle(colored ? Theme.feltLo : Theme.tileInk)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill)
                            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 3)
                    )
                    .rotationEffect(.degrees(Double((i % 3) + 1) * (i % 2 == 0 ? -2 : 2)))
            }
        }
    }
}
