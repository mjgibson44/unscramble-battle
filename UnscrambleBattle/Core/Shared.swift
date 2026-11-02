import Foundation
import UIKit
import AudioToolbox

/// Runs delayed work on the main queue; `cancelAll()` makes every pending item a no-op.
final class Scheduler {
    private var generation = 0

    func cancelAll() { generation += 1 }

    func after(_ seconds: Double, _ work: @escaping () -> Void) {
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self = self, self.generation == g else { return }
            work()
        }
    }
}

/// 3, 2, 1, then `done`.
func runCountdown(_ scheduler: Scheduler, say: @escaping (BoardMessage?) -> Void, then done: @escaping () -> Void) {
    for (i, n) in ["3", "2", "1"].enumerated() {
        scheduler.after(Double(i) * 0.75) {
            say(BoardMessage(title: n, big: true))
            Feedback.tick()
        }
    }
    scheduler.after(2.25) {
        Feedback.go()
        done()
    }
}

func ordinal(_ n: Int) -> String {
    let tens = n % 100
    if (11...13).contains(tens) { return "\(n)th" }
    switch n % 10 {
    case 1: return "\(n)st"
    case 2: return "\(n)nd"
    case 3: return "\(n)rd"
    default: return "\(n)th"
    }
}

/// Haptics plus short system sounds. Sound can be switched off on the menu.
enum Feedback {
    static var soundOn: Bool {
        UserDefaults.standard.object(forKey: "sound") as? Bool ?? true
    }

    private static func play(_ id: SystemSoundID) {
        if soundOn { AudioServicesPlaySystemSound(id) }
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        play(1104)
    }

    static func undo() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func wrong() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        play(1053)
    }

    static func win() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        play(1057)
    }

    static func lose() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func tick() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        play(1103)
    }

    static func go() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func fanfare() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        play(1025)
    }
}
