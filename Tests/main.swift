import Foundation

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
