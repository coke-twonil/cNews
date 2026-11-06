import SwiftUI
import UIKit

/// UIKit recognizers reject vertical movement without taking the scroll view's
/// pan gesture. A recognized swipe cancels taps in message rows.
struct HorizontalSwipe: UIViewRepresentable {
    var edgeOnly = false
    var enabled = true
    var action: (Int) -> Void
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        context.coordinator.probe = view
        return view
    }
    func updateUIView(_ view: Probe, context: Context) {
        context.coordinator.action = action
        context.coordinator.edgeOnly = edgeOnly
        context.coordinator.enabled = enabled
        view.attach()
    }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    static func dismantleUIView(_ view: Probe, coordinator: Coordinator) { coordinator.detach() }
    final class Probe: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        func attach() {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                var ancestor = self.superview
                while let view = ancestor {
                    if let scroll = view as? UIScrollView { self.coordinator?.attach(to: scroll); return }
                    ancestor = view.superview
                }
            }
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: (Int) -> Void
        var edgeOnly = false
        var enabled = true
        weak var scroll: UIScrollView?
        weak var probe: UIView?
        private var recognizers: [UISwipeGestureRecognizer] = []
        init(action: @escaping (Int) -> Void) { self.action = action }
        func attach(to scroll: UIScrollView) {
            guard self.scroll !== scroll else { return }
            detach(); self.scroll = scroll
            for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
                swipe.direction = direction
                swipe.delegate = self
                swipe.cancelsTouchesInView = true
                scroll.addGestureRecognizer(swipe)
                recognizers.append(swipe)
            }
        }
        func detach() {
            for recognizer in recognizers { scroll?.removeGestureRecognizer(recognizer) }
            recognizers.removeAll(); scroll = nil
        }
        @objc func swiped(_ gesture: UISwipeGestureRecognizer) {
            guard gesture.state == .ended else { return }
            action(gesture.direction == .left ? 1 : -1)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard enabled, let probe, let window = probe.window, let swipe = gestureRecognizer as? UISwipeGestureRecognizer else { return false }
            let atEdge = touch.location(in: window).x <= 24
            if edgeOnly { return atEdge && swipe.direction == .right }
            if atEdge && swipe.direction == .right { return false }
            return probe.bounds.contains(touch.location(in: probe))
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer === scroll?.panGestureRecognizer
        }
    }
}

/// Uses the same directional recognizer as message swipes, but accepts only
/// rightward gestures starting within the leftmost 24 points of the window.
struct EdgeBack: View {
    var active: Bool
    var action: () -> Void
    var body: some View {
        HorizontalSwipe(edgeOnly: true, enabled: active) { direction in
            if direction == -1 { action() }
        }
    }
}
