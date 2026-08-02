import SwiftUI
import UIKit

public struct TimelineGestureOverlay: UIViewRepresentable {
    let resetGeneration: Int
    let onInteractionBegan: @MainActor () -> Void
    let onPanChanged: @MainActor (_ translationX: CGFloat) -> Void
    let onPinchChanged: @MainActor (_ scale: CGFloat, _ centroidX: CGFloat) -> Void
    let onInteractionEnded: @MainActor (_ velocityX: CGFloat) -> Void
    let onInteractionCancelled: @MainActor () -> Void
    let onTap: @MainActor (_ location: CGPoint) -> Void

    public init(
        resetGeneration: Int = 0,
        onInteractionBegan: @escaping @MainActor () -> Void,
        onPanChanged: @escaping @MainActor (_ translationX: CGFloat) -> Void,
        onPinchChanged: @escaping @MainActor (_ scale: CGFloat, _ centroidX: CGFloat) -> Void,
        onInteractionEnded: @escaping @MainActor (_ velocityX: CGFloat) -> Void,
        onInteractionCancelled: @escaping @MainActor () -> Void,
        onTap: @escaping @MainActor (_ location: CGPoint) -> Void
    ) {
        self.resetGeneration = resetGeneration
        self.onInteractionBegan = onInteractionBegan
        self.onPanChanged = onPanChanged
        self.onPinchChanged = onPinchChanged
        self.onInteractionEnded = onInteractionEnded
        self.onInteractionCancelled = onInteractionCancelled
        self.onTap = onTap
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))

        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator
        tap.delegate = context.coordinator

        tap.require(toFail: pan)

        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)

        return view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.resetRecognizersIfNeeded(in: uiView)
    }

    @MainActor
    public class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TimelineGestureOverlay
        private var session = TimelineGestureSession()
        private var observedResetGeneration: Int
        private var isResettingRecognizers = false

        init(parent: TimelineGestureOverlay) {
            self.parent = parent
            self.observedResetGeneration = parent.resetGeneration
        }

        public func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer) ||
               (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer) {
                return true
            }
            return false
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard !isResettingRecognizers else { return }
            guard let view = recognizer.view else { return }

            switch recognizer.state {
            case .began:
                publish(session.begin(.pan), in: view)
            case .changed:
                guard session.acceptsChanges(from: .pan) else { return }
                let translationX = recognizer.translation(in: view).x
                parent.onPanChanged(translationX)
            case .ended:
                publish(
                    session.end(.pan, velocityX: recognizer.velocity(in: view).x),
                    in: view
                )
            case .cancelled, .failed:
                publish(session.cancel(.pan), in: view)
            default:
                break
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard !isResettingRecognizers else { return }
            guard let view = recognizer.view else { return }

            switch recognizer.state {
            case .began:
                publish(session.begin(.pinch), in: view)
            case .changed:
                guard session.acceptsChanges(from: .pinch) else { return }
                let scale = recognizer.scale
                let centroidX = recognizer.location(in: view).x
                parent.onPinchChanged(scale, centroidX)
            case .ended:
                publish(session.end(.pinch), in: view)
            case .cancelled, .failed:
                publish(session.cancel(.pinch), in: view)
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            if recognizer.state == .ended {
                let location = recognizer.location(in: view)
                parent.onTap(location)
            }
        }

        func resetRecognizersIfNeeded(in view: UIView) {
            guard observedResetGeneration != parent.resetGeneration else { return }
            observedResetGeneration = parent.resetGeneration
            resetActiveRecognizers(in: view)
        }

        private func publish(_ event: TimelineGestureSessionEvent, in view: UIView) {
            switch event {
            case .none:
                break
            case .began:
                parent.onInteractionBegan()
            case .settled(let velocityX):
                parent.onInteractionEnded(velocityX)
            case .cancelled:
                parent.onInteractionCancelled()
                resetActiveRecognizers(in: view)
            }
        }

        private func resetActiveRecognizers(in view: UIView) {
            session.reset()
            isResettingRecognizers = true
            defer { isResettingRecognizers = false }

            for recognizer in view.gestureRecognizers ?? []
            where recognizer is UIPanGestureRecognizer || recognizer is UIPinchGestureRecognizer {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
        }
    }
}
