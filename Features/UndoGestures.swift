import SwiftUI
import UIKit

/// Views where several fingers are music, not commands (pads, keys).
protocol MusicalTouchSurface: UIView {}

/// I90: tap with two fingers to undo and three fingers to redo, anywhere
/// except the pads and keyboards. A short toast confirms the change.
struct UndoGestureInstaller: UIViewRepresentable {
    let undo: () -> Bool
    let redo: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: InstallerView, context: Context) {
        context.coordinator.undo = undo; context.coordinator.redo = redo
    }
    static func dismantleUIView(_ view: InstallerView, coordinator: Coordinator) { coordinator.detach() }

    final class InstallerView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
        }
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var undo: () -> Bool = { false }
        var redo: () -> Bool = { false }
        private var recognizers: [UITapGestureRecognizer] = []

        func attach(to window: UIWindow) {
            detach()
            for touches in [2, 3] {
                let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
                tap.numberOfTouchesRequired = touches
                tap.cancelsTouchesInView = false
                tap.delaysTouchesBegan = false
                tap.delaysTouchesEnded = false
                tap.delegate = self
                window.addGestureRecognizer(tap)
                recognizers.append(tap)
            }
            // Three fingers must not also count as two.
            if recognizers.count == 2 { recognizers[0].require(toFail: recognizers[1]) }
        }

        func detach() {
            for recognizer in recognizers { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizers = []
        }

        @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let done = recognizer.numberOfTouchesRequired == 2 ? undo() : redo()
            if done { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is MusicalTouchSurface || current is UITextField || current is UITextView { return false }
                // Views that zoom with two fingers (piano roll): a short pinch must never read as undo.
                if current.gestureRecognizers?.contains(where: { $0 is UIPinchGestureRecognizer }) == true { return false }
                view = current.superview
            }
            return true
        }

        /// Any pinch in progress wins over a two- or three-finger tap.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            other is UIPinchGestureRecognizer
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
