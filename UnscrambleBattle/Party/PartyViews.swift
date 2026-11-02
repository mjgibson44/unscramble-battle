import SwiftUI

struct PartyView: View {
    let exit: () -> Void
    @StateObject private var party = PartyController()
    @AppStorage("playerName") private var name = ""
    private let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch party.phase {
            case .setup:
                PartySetupView(
                    name: $name,
                    host: { party.host(name: name) },
                    join: { party.browse(name: name) },
                    back: exit
                )
            case .browsing:
                PartyBrowseView(party: party)
            case .lobby:
                PartyLobbyView(party: party)
            case .countdown, .playing, .roundOver:
                PartyGameView(party: party)
            case .gameOver:
                PartyGameOverView(party: party)
            case .ended(let reason):
                PartyEndedView(reason: reason, ok: { party.leave() })
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onReceive(ticker) { _ in party.tick() }
        .onDisappear { party.leave() }
    }
}

// MARK: - Setup

struct PartySetupView: View {
    @Binding var name: String
    let host: () -> Void
    let join: () -> Void
    let back: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TopBar(title: "Party", back: back)

                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR NAME")
                        .font(Theme.body(12, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                    TextField("", text: $name, prompt: Text("Type your name").foregroundColor(Theme.muted))
                        .font(Theme.display(24))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.feltHi))
                        .onChange(of: name) { newValue in
                            if newValue.count > 16 { name = String(newValue.prefix(16)) }
                        }
                }

                Text("Everyone opens Party on their own iPhone, close together. One person hosts and everyone else joins. Up to 6 players.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 14) {
                    Button("Host a game") { nameFocused = false; host() }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.players[2], fullWidth: true))
                    Button("Join a game") { nameFocused = false; join() }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.players[1], fullWidth: true))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("POINTS EACH ROUND")
                        .font(Theme.body(12, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                    PointsTable()
                    Text("Finishing 5th or 6th, or not solving it in time, scores nothing.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Browse

struct PartyBrowseView: View {
    @ObservedObject var party: PartyController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TopBar(title: "Join a game", back: { party.leave() })

            if party.nearby.isEmpty {
                HStack(spacing: 12) {
                    ProgressView().tint(Theme.muted)
                    Text("Looking for games nearby…").font(Theme.body(17, weight: .bold))
                }
                .padding(.top, 8)
                Text("Ask the host to open Party and tap Host a game. Keep Wi-Fi and Bluetooth on.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(party.nearby) { game in
                    Button { party.join(game) } label: {
                        HStack {
                            Text("\(game.hostName)'s game")
                                .font(Theme.display(20))
                                .lineLimit(1)
                            Spacer()
                            if party.joining == game.peer {
                                ProgressView().tint(Theme.text)
                            } else {
                                Text("Join")
                                    .font(Theme.body(15, weight: .heavy))
                                    .foregroundStyle(Theme.players[1])
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.feltHi))
                    }
                    .buttonStyle(.plain)
                    .disabled(party.joining != nil)
                }
            }

            if let error = party.joinError {
                Text(error).font(Theme.body(15, weight: .bold)).foregroundStyle(Theme.bad)
            }
            Spacer()
        }
    }
}

// MARK: - Lobby

struct PartyLobbyView: View {
    @ObservedObject var party: PartyController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TopBar(title: "Lobby", backLabel: "Leave", back: { party.leave() })

                Text("\(party.players.count) of \(PartyController.maxPlayers) players")
                    .font(Theme.body(12, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)

                VStack(spacing: 8) {
                    ForEach(party.players) { p in
                        PlayerRow(player: p, isMe: p.id == party.myId, tag: p.id == party.hostId ? "Host" : nil)
                    }
                }

                if party.isHost {
                    CountStepper(label: "Rounds", value: $party.rounds, range: 1...10)
                    Button("Start game") { party.startGame() }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.players[2], fullWidth: true))
                        .disabled(!party.canStart)
                        .opacity(party.canStart ? 1 : 0.4)
                    if party.players.count < 2 {
                        Text("Waiting for at least one more player to join.")
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.muted)
                        Text("Waiting for the host to start · \(party.totalRounds) rounds")
                            .font(Theme.body(15, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("POINTS EACH ROUND")
                        .font(Theme.body(12, weight: .heavy))
                        .foregroundStyle(Theme.muted)
                    PointsTable()
                }
                .padding(.top, 8)
            }
        }
    }
}

struct PlayerRow: View {
    let player: PartyPlayer
    let isMe: Bool
    var tag: String? = nil
    var trailing: String? = nil

    var body: some View {
        let color = Theme.player(player.color)
        return HStack(spacing: 12) {
            Text(String(player.name.prefix(1)).uppercased())
                .font(Theme.display(20))
                .foregroundStyle(Theme.feltLo)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
            Text(player.name + (isMe ? " (you)" : ""))
                .font(Theme.body(17, weight: .bold))
                .lineLimit(1)
            if let tag = tag {
                Text(tag.uppercased())
                    .font(Theme.body(11, weight: .heavy))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.feltLo))
            }
            Spacer()
            if let trailing = trailing {
                Text(trailing)
                    .font(Theme.display(22))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isMe ? Theme.feltHi : Theme.feltHi.opacity(0.6)))
    }
}

// MARK: - Playing

struct PartyGameView: View {
    @ObservedObject var party: PartyController
    @State private var leaveArmed = false

    private var myColor: Color { Theme.player(party.me?.color ?? 0) }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 14) {
                HStack {
                    Button(leaveArmed ? "Tap again" : "Leave") {
                        if leaveArmed { party.leave() } else {
                            leaveArmed = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { leaveArmed = false }
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                    Spacer()
                    Text("Round \(party.roundNumber) of \(party.totalRounds)")
                        .font(Theme.display(18))
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }

                FillBar(
                    fraction: party.phase == .roundOver ? 0 : party.timeLeft,
                    color: party.timeLeft < 0.22 ? Theme.bad : myColor
                )

                PlayerStrip(party: party)

                Spacer(minLength: 0)
                BoardView(model: party.board, color: myColor, width: geo.size.width, maxTile: 64, message: party.message)
                Button("Clear") { party.board.clear() }
                    .buttonStyle(PillButtonStyle())
                    .opacity(party.phase == .playing && !party.board.locked ? 1 : 0)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Everyone's score, plus their finishing place this round once they've solved it.
struct PlayerStrip: View {
    @ObservedObject var party: PartyController

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
            ForEach(party.players) { p in
                chip(for: p)
            }
        }
    }

    private func chip(for p: PartyPlayer) -> some View {
        let color = Theme.player(p.color)
        let place = party.finishers.firstIndex(of: p.id)
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(p.id == party.myId ? "You" : p.name)
                .font(Theme.body(13, weight: .heavy))
                .lineLimit(1)
            Spacer(minLength: 2)
            if let place = place {
                Text(ordinal(place + 1))
                    .font(Theme.body(12, weight: .heavy))
                    .foregroundStyle(Theme.feltLo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(color))
            } else {
                Text("\(p.score)")
                    .font(Theme.display(15))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Theme.feltHi))
        .animation(.spring(response: 0.3), value: place)
    }
}

// MARK: - Game over

struct PartyGameOverView: View {
    @ObservedObject var party: PartyController

    var body: some View {
        let standings = party.standings
        let winners = standings.filter { $0.rank == 1 }.map { $0.player }
        return ScrollView {
            VStack(spacing: 18) {
                Text("Final standings")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 16)
                Text(headline(winners))
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.player(winners.first?.color ?? 0))
                    .multilineTextAlignment(.center)

                VStack(spacing: 8) {
                    ForEach(standings) { entry in
                        HStack(spacing: 10) {
                            Text(ordinal(entry.rank))
                                .font(Theme.display(18))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 44, alignment: .leading)
                            PlayerRow(
                                player: entry.player,
                                isMe: entry.player.id == party.myId,
                                trailing: "\(entry.player.score)"
                            )
                        }
                    }
                }

                if party.isHost {
                    Button("Play again") { party.backToLobby() }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.players[2], fullWidth: true))
                } else {
                    Text("The host can start another game.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.muted)
                }
                Button("Leave") { party.leave() }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.feltLo, foreground: Theme.text, fullWidth: true))
            }
        }
    }

    private func headline(_ winners: [PartyPlayer]) -> String {
        if winners.contains(where: { $0.id == party.myId }) {
            return winners.count > 1 ? "You tied for 1st!" : "You win!"
        }
        if winners.count > 1 { return "It's a tie!" }
        return "\(winners.first?.name ?? "Someone") wins!"
    }
}

struct PartyEndedView: View {
    let reason: String
    let ok: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Game ended")
                .font(Theme.display(30))
            Text(reason)
                .font(Theme.body(17))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("OK", action: ok)
                .buttonStyle(ChunkyButtonStyle(color: Theme.players[2]))
            Spacer()
        }
    }
}
