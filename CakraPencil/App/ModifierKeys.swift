import UIKit

/// Shift / ⌘ held on a hardware keyboard (Mac, iPad with keyboard). Mouse clicks on Mac Catalyst don't always carry
/// the modifier keys, and the GameController keyboard can need Input Monitoring on macOS, so the keys are also
/// tracked from key presses that reach the app delegate and from pointer hovering.
@MainActor
enum ModifierKeys {
    private(set) static var pressed: UIKeyModifierFlags = []
    /// From the last pointer hover over the map (UIHoverGestureRecognizer.modifierFlags).
    static var hover: UIKeyModifierFlags = []

    static func update(_ presses: Set<UIPress>, down: Bool) {
        for press in presses {
            guard let key = press.key else { continue }
            let flag: UIKeyModifierFlags? = switch key.keyCode {
            case .keyboardLeftShift, .keyboardRightShift: .shift
            case .keyboardLeftGUI, .keyboardRightGUI: .command
            case .keyboardLeftAlt, .keyboardRightAlt: .alternate
            default: nil
            }
            if let flag {
                if down { pressed.insert(flag) } else { pressed.remove(flag); hover.remove(flag) }
            } else {
                // Any other key: its modifier flags are the keys held right now.
                pressed = key.modifierFlags.intersection([.shift, .command, .alternate])
            }
        }
    }

    /// The window lost focus (e.g. ⌘-Tab): a key released elsewhere would otherwise stay "held".
    static func reset() {
        pressed = []
        hover = []
    }
}

/// Receives the key presses no view handled (modifier keys alone are never handled), for `ModifierKeys`.
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ModifierKeys.reset() }
        }
        return true
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        ModifierKeys.update(presses, down: true)
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        ModifierKeys.update(presses, down: false)
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        ModifierKeys.update(presses, down: false)
        super.pressesCancelled(presses, with: event)
    }
}
