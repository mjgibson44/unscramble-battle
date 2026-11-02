import SwiftUI

@main
struct UnscrambleBattleApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

enum Screen: Hashable {
    case menu, solo, party
}

struct RootView: View {
    @State private var screen: Screen = .menu

    var body: some View {
        ZStack {
            Theme.felt.ignoresSafeArea()
            switch screen {
            case .menu:
                MenuView(go: { screen = $0 })
            case .solo:
                SoloView(exit: { screen = .menu })
            case .party:
                PartyView(exit: { screen = .menu })
            }
        }
        .foregroundStyle(Theme.text)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    }
}
