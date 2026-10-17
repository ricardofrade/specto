import SwiftUI
#if os(iOS)
import UIKit

/// ←/→ on a hardware keyboard while the player is on screen. A first-responder view with key
/// commands that take priority over keyboard navigation (plain arrows otherwise move focus).
/// Unlike making the player focusable, this keeps the app idle between key presses.
struct ArrowKeys: UIViewRepresentable {
    let onArrow: (_ forward: Bool) -> Void

    func makeUIView(context: Context) -> KeyView {
        let view = KeyView()
        view.onArrow = onArrow
        return view
    }

    func updateUIView(_ view: KeyView, context: Context) {
        view.onArrow = onArrow
    }

    final class KeyView: UIView {
        var onArrow: (Bool) -> Void = { _ in }

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { becomeFirstResponder() }
        }

        override var keyCommands: [UIKeyCommand]? {
            [UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow].map { input in
                let command = UIKeyCommand(input: input, modifierFlags: [], action: #selector(arrow(_:)))
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
        }

        @objc private func arrow(_ command: UIKeyCommand) {
            onArrow(command.input == UIKeyCommand.inputRightArrow)
        }
    }
}
#endif
