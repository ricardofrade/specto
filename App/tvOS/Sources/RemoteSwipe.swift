import SwiftUI
import UIKit

/// Reports horizontal swipes on the Siri Remote's touch surface. SwiftUI has no gesture for the
/// remote's (indirect) touches, so a pan recogniser goes on the window while this view is shown.
struct RemoteSwipe: UIViewRepresentable {
    /// Horizontal translation so far (points, roughly −1000…1000 across the surface), or nil when it ends.
    let onChange: (CGFloat?) -> Void

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.onChange = onChange
    }

    static func dismantleUIView(_ view: CatcherView, coordinator: ()) {
        view.detach()
    }

    final class CatcherView: UIView {
        var onChange: (CGFloat?) -> Void = { _ in }
        private var pan: UIPanGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            pan.cancelsTouchesInView = false
            window.addGestureRecognizer(pan)
            self.pan = pan
        }

        func detach() {
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            pan = nil
        }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed: onChange(recognizer.translation(in: recognizer.view).x)
            default: onChange(nil)
            }
        }
    }
}
