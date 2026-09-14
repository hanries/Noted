import SwiftUI

#if os(iOS)
import UIKit
struct PointerSurface: UIViewRepresentable {
    var pencilOnly: Bool
    var panMode: Bool
    var began: (InkPoint) -> Void
    var moved: (InkPoint) -> Void
    var ended: (Bool) -> Void
    var panned: (CGSize) -> Void
    var magnified: (Double, CGPoint) -> Void
    var pencilTapped: () -> Void

    func makeUIView(context: Context) -> CaptureView { CaptureView() }
    func updateUIView(_ view: CaptureView, context: Context) {
        if view.panMode != panMode || view.pencilOnly != pencilOnly { view.cancelInk() }
        view.pencilOnly = pencilOnly; view.panMode = panMode
        view.pan.minimumNumberOfTouches = panMode ? 1 : 2
        view.began = began; view.moved = moved; view.ended = ended
        view.panned = panned; view.magnified = magnified; view.pencilTapped = pencilTapped
    }
    final class CaptureView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        var pencilOnly = true
        var panMode = false
        var began: (InkPoint) -> Void = { _ in }
        var moved: (InkPoint) -> Void = { _ in }
        var ended: (Bool) -> Void = { _ in }
        var panned: (CGSize) -> Void = { _ in }
        var magnified: (Double, CGPoint) -> Void = { _, _ in }
        var pencilTapped: () -> Void = {}
        var active: UITouch?
        lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(panPage(_:)))
        lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoomPage(_:)))

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true; isOpaque = false; backgroundColor = .clear
            pan.minimumNumberOfTouches = 2
            for recognizer in [pan, pinch] {
                recognizer.delegate = self
                recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                addGestureRecognizer(recognizer)
            }
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
            pan.allowedScrollTypesMask = .all
            let interaction = UIPencilInteraction(); interaction.delegate = self; addInteraction(interaction)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            active?.type != .pencil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (gestureRecognizer === pan && other === pinch) || (gestureRecognizer === pinch && other === pan)
        }
        @objc func panPage(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { cancelInk() }
            if gesture.state == .began || gesture.state == .changed {
                let delta = gesture.translation(in: self)
                panned(CGSize(width: delta.x, height: delta.y)); gesture.setTranslation(.zero, in: self)
            }
        }
        @objc func zoomPage(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began { cancelInk() }
            if gesture.state == .began || gesture.state == .changed {
                magnified(Double(gesture.scale), gesture.location(in: self)); gesture.scale = 1
            }
        }
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) { handlePencilTap() }
        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) { handlePencilTap() }
        private func handlePencilTap() {
            guard UIPencilInteraction.preferredTapAction != .ignore else { return }
            cancelInk(); pencilTapped()
        }
        func cancelInk() {
            guard active != nil else { return }
            active = nil; ended(true)
        }
        func point(_ touch: UITouch) -> InkPoint {
            let p = touch.location(in: self)
            let pressure = touch.type == .pencil && touch.maximumPossibleForce > 0 ? Double(touch.force / touch.maximumPossibleForce) : 1
            return InkPoint(x: p.x, y: p.y, pressure: max(0.15, min(1, pressure)))
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            let fingers = event?.allTouches?.filter { $0.type != .pencil && $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
            if fingers >= 2 {
                if active?.type != .pencil { cancelInk() }
                return
            }
            guard !panMode, active == nil, pan.state != .changed, pinch.state != .changed,
                  let touch = touches.first(where: { !pencilOnly || $0.type == .pencil }) else { return }
            active = touch; began(point(touch))
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let active, touches.contains(active) else { return }
            for touch in event?.coalescedTouches(for: active) ?? [active] { moved(point(touch)) }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = active, touches.contains(touch) else { return }
            moved(point(touch)); active = nil; ended(false)
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = active, touches.contains(touch) else { return }
            cancelInk()
        }
    }
}
#else
import AppKit
struct PointerSurface: NSViewRepresentable {
    var pencilOnly: Bool
    var panMode: Bool
    var began: (InkPoint) -> Void
    var moved: (InkPoint) -> Void
    var ended: (Bool) -> Void
    var panned: (CGSize) -> Void
    var magnified: (Double, CGPoint) -> Void
    var pencilTapped: () -> Void
    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.panMode = panMode; view.began = began; view.moved = moved; view.ended = ended
        view.panned = panned; view.magnified = magnified
    }
    final class CaptureView: NSView {
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        var panMode = false
        var dragging = false
        var movingPage = false
        var previousPoint = CGPoint.zero
        var began: (InkPoint) -> Void = { _ in }
        var moved: (InkPoint) -> Void = { _ in }
        var ended: (Bool) -> Void = { _ in }
        var panned: (CGSize) -> Void = { _ in }
        var magnified: (Double, CGPoint) -> Void = { _, _ in }
        func point(_ event: NSEvent) -> InkPoint {
            let p = convert(event.locationInWindow, from: nil)
            return InkPoint(x: p.x, y: p.y)
        }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self); dragging = true; movingPage = panMode
            previousPoint = convert(event.locationInWindow, from: nil)
            if !movingPage { began(point(event)) }
        }
        override func mouseDragged(with event: NSEvent) {
            guard dragging else { return }
            if movingPage {
                let p = convert(event.locationInWindow, from: nil)
                panned(CGSize(width: p.x - previousPoint.x, height: p.y - previousPoint.y)); previousPoint = p
            } else { moved(point(event)) }
        }
        override func mouseUp(with event: NSEvent) {
            guard dragging else { return }
            if !movingPage { moved(point(event)); ended(false) }
            dragging = false
        }
        override func scrollWheel(with event: NSEvent) {
            guard !dragging else { return }
            let multiplier = event.hasPreciseScrollingDeltas ? 1.0 : 16.0
            panned(CGSize(width: event.scrollingDeltaX * multiplier, height: event.scrollingDeltaY * multiplier))
        }
        override func magnify(with event: NSEvent) {
            guard !dragging else { return }
            magnified(1 + event.magnification, convert(event.locationInWindow, from: nil))
        }
    }
}
#endif
