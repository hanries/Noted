import SwiftUI

// The canvas shares the document format and rendering on both platforms.
// Native input captures Pencil pressure and rejects fingers while Pencil-only is enabled.
#if os(iOS)
import UIKit
struct PointerSurface: UIViewRepresentable {
    var pencilOnly: Bool
    var began: (InkPoint) -> Void
    var moved: (InkPoint) -> Void
    var ended: (Bool) -> Void
    func makeUIView(context: Context) -> CaptureView {
        let view = CaptureView(); view.isMultipleTouchEnabled = true; return view
    }
    func updateUIView(_ view: CaptureView, context: Context) {
        view.pencilOnly = pencilOnly; view.began = began; view.moved = moved; view.ended = ended
        view.isOpaque = false; view.backgroundColor = .clear
    }
    final class CaptureView: UIView {
        var pencilOnly = false
        var began: (InkPoint) -> Void = { _ in }
        var moved: (InkPoint) -> Void = { _ in }
        var ended: (Bool) -> Void = { _ in }
        var active: UITouch?
        func point(_ touch: UITouch) -> InkPoint {
            let p = touch.location(in: self)
            let pressure = touch.type == .pencil && touch.maximumPossibleForce > 0 ? Double(touch.force / touch.maximumPossibleForce) : 1
            return InkPoint(x: p.x, y: p.y, pressure: max(0.15, min(1, pressure)))
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard active == nil, let touch = touches.first(where: { !pencilOnly || $0.type == .pencil }) else { return }
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
            active = nil; ended(true)
        }
    }
}
#else
import AppKit
struct PointerSurface: NSViewRepresentable {
    var pencilOnly: Bool
    var began: (InkPoint) -> Void
    var moved: (InkPoint) -> Void
    var ended: (Bool) -> Void
    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.began = began; view.moved = moved; view.ended = ended
    }
    final class CaptureView: NSView {
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        var began: (InkPoint) -> Void = { _ in }
        var moved: (InkPoint) -> Void = { _ in }
        var ended: (Bool) -> Void = { _ in }
        func point(_ event: NSEvent) -> InkPoint {
            let p = convert(event.locationInWindow, from: nil)
            return InkPoint(x: p.x, y: p.y)
        }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); began(point(event)) }
        override func mouseDragged(with event: NSEvent) { moved(point(event)) }
        override func mouseUp(with event: NSEvent) { moved(point(event)); ended(false) }
    }
}
#endif
