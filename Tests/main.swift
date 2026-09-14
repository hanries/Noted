import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError("FAIL: \(label)") }
    print("PASS: \(label)")
}
var book = Notebook(title: "Round-trip notebook")
let stroke = InkStroke(points: [InkPoint(x: 10, y: 20, pressure: 0.4), InkPoint(x: 110, y: 20, pressure: 0.9)])
book.pages[0].strokes = [stroke]
book.pages[0].texts = [TextCard(text: "Math ∫ — 中文", x: 60, y: 90)]
book.pages.append(NotePage(paper: .grid))
let encoded = try book.encoded()
let reopened = try Notebook.decode(encoded)
check(reopened == book, "Multiple pages, text, pressure and IDs survive save/reopen")
check(stroke.distance(to: InkPoint(x: 60, y: 23)) == 3, "Eraser detects a segment between samples")
check(stroke.distance(to: InkPoint(x: 120, y: 20)) == 10, "Selection clamps to segment endpoints")
let moved = stroke.translated(x: 25, y: -5)
check(moved.points[0].x == 35 && moved.points[0].y == 15 && moved.points[0].pressure == 0.4, "Moving preserves pressure")
check(moved.id == stroke.id && stroke.points[0].x == 10, "Moving preserves identity and original snapshot")
var invalid = book; invalid.version = 2
check((try? Notebook.decode(invalid.encoded())) == nil, "Future file versions rejected without overwriting")
invalid = book; invalid.pages = []
check((try? Notebook.decode(invalid.encoded())) == nil, "Empty notebook rejected safely")
invalid = book; invalid.pages.append(invalid.pages[0])
check((try? Notebook.decode(invalid.encoded())) == nil, "Duplicate page IDs rejected")
invalid = book; invalid.pages[0].strokes[0].width = -4
check((try? Notebook.decode(invalid.encoded())) == nil, "Invalid stroke widths rejected")
check((try? Notebook.decode(Data("not a notebook".utf8))) == nil, "Corrupted files rejected safely")

let viewportSize = CGSize(width: 800, height: 900)
var viewport = NotebookViewport()
let center = CGPoint(x: 400, y: 450)
let centerPoint = InkPoint(x: 400, y: 450, pressure: 0.6)
let beforeZoom = viewport.pagePoint(centerPoint, in: viewportSize)
viewport.magnify(2, at: center, in: viewportSize)
check(viewport.pagePoint(centerPoint, in: viewportSize) == beforeZoom, "Pinch preserves the page point under the anchor")
let offsetAnchor = CGPoint(x: 440, y: 490)
let anchorPoint = InkPoint(x: offsetAnchor.x, y: offsetAnchor.y)
let beforeOffsetZoom = viewport.pagePoint(anchorPoint, in: viewportSize)
viewport.magnify(1.2, at: offsetAnchor, in: viewportSize)
let afterOffsetZoom = viewport.pagePoint(anchorPoint, in: viewportSize)
check(abs(beforeOffsetZoom.x - afterOffsetZoom.x) < 0.0001 && abs(beforeOffsetZoom.y - afterOffsetZoom.y) < 0.0001, "Off-center pinch keeps its focal point stable")
viewport.pan(CGSize(width: -50, height: 80), in: viewportSize)
let pagePoint = InkPoint(x: 200, y: 350, pressure: 0.6)
let origin = viewport.origin(in: viewportSize), scale = viewport.scale(in: viewportSize)
let screenPoint = InkPoint(x: origin.x + pagePoint.x * scale, y: origin.y + pagePoint.y * scale, pressure: pagePoint.pressure)
let mapped = viewport.pagePoint(screenPoint, in: viewportSize)
check(abs(mapped.x - pagePoint.x) < 0.0001 && abs(mapped.y - pagePoint.y) < 0.0001 && mapped.pressure == pagePoint.pressure, "Ink coordinates and pressure remain correct after pan and zoom")
viewport.pan(CGSize(width: 1e9, height: -1e9), in: viewportSize)
let boundedOrigin = viewport.origin(in: viewportSize)
check(boundedOrigin.x <= 22.001 && boundedOrigin.y + 1024 * scale >= viewportSize.height - 22.001, "Panning cannot lose the page beyond the viewport")
viewport.magnify(0.001, at: center, in: viewportSize)
check(viewport.zoom == 1 && viewport.offset == .zero, "Zooming back to fit recenters the page")
viewport.magnify(100, at: center, in: viewportSize)
check(viewport.zoom == 4, "Zoom has a bounded maximum")
let validViewport = viewport
viewport.magnify(.nan, at: center, in: viewportSize)
check(viewport == validViewport, "Invalid magnification cannot corrupt the viewport")

var continuation = Notebook(pages: [NotePage(paper: .grid)])
let lastID = continuation.pages[0].id
check(!continuation.appendContinuationPage(after: lastID), "An empty final page does not spawn more empty pages")
continuation.pages[0].strokes = [stroke]
let beforeContinuation = continuation
check(continuation.appendContinuationPage(after: lastID), "Writing on the last page creates a continuation page")
check(continuation.pages.count == 2 && continuation.pages[1].paper == .grid && continuation.pages[1].strokes.isEmpty, "Continuation page inherits the template and starts empty")
check(!continuation.appendContinuationPage(after: lastID) && continuation.pages.count == 2, "Further writing on the earlier page does not create duplicate spare pages")
let reopenedContinuation = try Notebook.decode(continuation.encoded())
check(reopenedContinuation == continuation, "Automatic pages round-trip through the existing file format")
continuation = beforeContinuation
check(continuation.pages.count == 1 && continuation.pages[0].strokes == [stroke], "A snapshot restores notebook content before automatic page creation")
