import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

struct InkPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var pressure: Double = 1
}

struct InkStroke: Codable, Identifiable, Equatable {
    var id = UUID()
    var points: [InkPoint]
    var color: String = "ink"
    var width: Double = 2.5
    var isHighlighter = false

    func distance(to point: InkPoint) -> Double {
        guard let first = points.first else { return .infinity }
        var best = hypot(first.x - point.x, first.y - point.y)
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length == 0 ? 0 : max(0, min(1, ((point.x-a.x)*dx + (point.y-a.y)*dy)/length))
            best = min(best, hypot(point.x-a.x-t*dx, point.y-a.y-t*dy))
        }
        return best
    }

    func translated(x: Double, y: Double) -> InkStroke {
        var copy = self
        copy.points = points.map { InkPoint(x: $0.x + x, y: $0.y + y, pressure: $0.pressure) }
        return copy
    }
}

struct TextCard: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var x: Double = 90
    var y: Double = 90
}

enum Paper: String, Codable, CaseIterable {
    case ruled = "Ruled", grid = "Grid", blank = "Blank"
}

struct NotePage: Codable, Identifiable, Equatable {
    var id = UUID()
    var paper: Paper = .ruled
    var strokes: [InkStroke] = []
    var texts: [TextCard] = []
}

struct Notebook: Codable, Equatable {
    var version = 1
    var title = "Untitled notebook"
    var pages: [NotePage] = [NotePage()]

    static func decode(_ data: Data) throws -> Notebook {
        let book = try JSONDecoder().decode(Notebook.self, from: data)
        guard book.version == 1, !book.pages.isEmpty,
              Set(book.pages.map(\.id)).count == book.pages.count else { throw NotebookError.invalidFormat }
        for page in book.pages {
            guard Set(page.strokes.map(\.id)).count == page.strokes.count,
                  Set(page.texts.map(\.id)).count == page.texts.count,
                  page.strokes.allSatisfy({ stroke in
                      stroke.width.isFinite && stroke.width > 0 && stroke.width <= 100 &&
                      stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.pressure.isFinite && $0.pressure >= 0 && $0.pressure <= 1 }
                  }), page.texts.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw NotebookError.invalidFormat }
        }
        return book
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

enum NotebookError: Error { case invalidFormat }

// Viewport state never enters the document or undo history.
struct NotebookViewport: Equatable {
    var zoom: Double = 1
    var offset: CGSize = .zero
    var pageCount = 1

    func scale(in size: CGSize) -> Double {
        max(0.1, min((size.width - 44) / 768, (size.height - 44) / 1024)) * zoom
    }
    func origin(in size: CGSize) -> CGPoint {
        let s = scale(in: size)
        return CGPoint(x: (size.width - 768 * s) / 2 + offset.width,
                       y: (size.height - 1024 * s) / 2 + offset.height)
    }
    func pagePoint(_ point: InkPoint, in size: CGSize) -> InkPoint {
        let o = origin(in: size), s = scale(in: size)
        return InkPoint(x: (point.x - o.x) / s, y: (point.y - o.y) / s, pressure: point.pressure)
    }
    func pageStride(in size: CGSize) -> Double { 1024 * scale(in: size) + 24 }
    func pageOrigin(at index: Int, in size: CGSize) -> CGPoint {
        let first = origin(in: size)
        return CGPoint(x: first.x, y: first.y + Double(index) * pageStride(in: size))
    }
    func pageIndex(at point: InkPoint, in size: CGSize) -> Int? {
        let first = origin(in: size), s = scale(in: size)
        let index = Int(floor((point.y - first.y) / pageStride(in: size)))
        guard (0..<pageCount).contains(index) else { return nil }
        let y = point.y - pageOrigin(at: index, in: size).y
        guard (0...(768 * s)).contains(point.x - first.x), (0...(1024 * s)).contains(y) else { return nil }
        return index
    }
    func pagePoint(_ point: InkPoint, at index: Int, in size: CGSize) -> InkPoint {
        let o = pageOrigin(at: index, in: size), s = scale(in: size)
        return InkPoint(x: (point.x - o.x) / s, y: (point.y - o.y) / s, pressure: point.pressure)
    }
    mutating func showPage(_ index: Int, in size: CGSize) {
        offset.height = -Double(index) * pageStride(in: size); clamp(in: size)
    }
    // Returns downward movement beyond the final page. Only a pan can request a new page.
    @discardableResult
    mutating func pan(_ delta: CGSize, in size: CGSize) -> Double {
        let desiredY = offset.height + delta.height
        offset.width += delta.width; offset.height = desiredY; clamp(in: size)
        return max(0, offset.height - desiredY)
    }
    mutating func magnify(_ factor: Double, at anchor: CGPoint, in size: CGSize) {
        guard factor.isFinite, factor > 0 else { return }
        let oldOrigin = origin(in: size)
        let anchoredPage = max(0, min(pageCount - 1, Int(floor((anchor.y - oldOrigin.y) / pageStride(in: size)))))
        let p = pagePoint(InkPoint(x: anchor.x, y: anchor.y), at: anchoredPage, in: size)
        zoom = min(4, max(1, zoom * factor))
        let s = scale(in: size)
        offset = CGSize(width: anchor.x - p.x * s - (size.width - 768 * s) / 2,
                        height: anchor.y - p.y * s - Double(anchoredPage) * pageStride(in: size) - (size.height - 1024 * s) / 2)
        clamp(in: size)
    }
    mutating func clamp(in size: CGSize) {
        let s = scale(in: size)
        let x = max(0, (768 * s - size.width) / 2 + 22)
        let y = max(0, (1024 * s - size.height) / 2 + 22)
        offset.width = min(x, max(-x, offset.width)); offset.height = min(y, max(-y - Double(max(0, pageCount - 1)) * pageStride(in: size), offset.height))
    }
}

extension Notebook {
    @discardableResult
    mutating func appendPageAfterScroll(after pageID: UUID) -> Bool {
        guard let last = pages.last, last.id == pageID else { return false }
        pages.append(NotePage(paper: last.paper)); return true
    }
}


extension NotePage {
    func text(at point: InkPoint) -> TextCard? {
        texts.last { ( $0.x...($0.x + 300) ).contains(point.x) && ( $0.y...($0.y + 90) ).contains(point.y) }
    }
    // New blank drafts do not create objects in the saved notebook.
    mutating func updateText(id: UUID, text: String, x: Double, y: Double) {
        if let index = texts.firstIndex(where: { $0.id == id }) { texts[index].text = text }
        else if !text.isEmpty { texts.append(TextCard(id: id, text: text, x: x, y: y)) }
    }
}

// Selection is transient editor state, never part of the saved file format.
struct PageSelection: Equatable {
    var strokes: Set<UUID> = []
    var texts: Set<UUID> = []
    var count: Int { strokes.count + texts.count }

    func bounds(in page: NotePage) -> CGRect? {
        var result = CGRect.null
        for stroke in page.strokes where strokes.contains(stroke.id) {
            for point in stroke.points {
                result = result.union(CGRect(x: point.x - stroke.width / 2, y: point.y - stroke.width / 2,
                                             width: stroke.width, height: stroke.width))
            }
        }
        for text in page.texts where texts.contains(text.id) {
            result = result.union(CGRect(x: text.x, y: text.y, width: 300, height: 90))
        }
        return result.isNull ? nil : result
    }

    func moving(_ original: NotePage, by delta: CGSize) -> NotePage {
        guard let bounds = bounds(in: original), delta.width.isFinite, delta.height.isFinite else { return original }
        // Clamp the whole group once so spacing stays intact, including near page edges.
        let dx = min(max(0, 768 - bounds.maxX), max(min(0, -bounds.minX), delta.width))
        let dy = min(max(0, 1024 - bounds.maxY), max(min(0, -bounds.minY), delta.height))
        var moved = original
        for i in moved.strokes.indices where strokes.contains(moved.strokes[i].id) {
            moved.strokes[i] = original.strokes[i].translated(x: dx, y: dy)
        }
        for i in moved.texts.indices where texts.contains(moved.texts[i].id) {
            moved.texts[i].x += dx; moved.texts[i].y += dy
        }
        return moved
    }
}

struct LassoRegion {
    let points: [InkPoint]
    private let edges: [(InkPoint, InkPoint)]
    init(points: [InkPoint]) {
        self.points = points
        edges = points.first.map { Array(zip(points, Array(points.dropFirst()) + [$0])) } ?? []
    }
    private func onSegment(_ p: InkPoint, _ a: InkPoint, _ b: InkPoint) -> Bool {
        abs(cross(a, b, p)) < 0.000001 &&
        p.x >= min(a.x, b.x) - 0.000001 && p.x <= max(a.x, b.x) + 0.000001 &&
        p.y >= min(a.y, b.y) - 0.000001 && p.y <= max(a.y, b.y) + 0.000001
    }
    private func cross(_ a: InkPoint, _ b: InkPoint, _ c: InkPoint) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
    private func intersects(_ a: InkPoint, _ b: InkPoint, _ c: InkPoint, _ d: InkPoint) -> Bool {
        let abC = cross(a, b, c), abD = cross(a, b, d), cdA = cross(c, d, a), cdB = cross(c, d, b)
        if ((abC > 0 && abD < 0) || (abC < 0 && abD > 0)) &&
           ((cdA > 0 && cdB < 0) || (cdA < 0 && cdB > 0)) { return true }
        return onSegment(c, a, b) || onSegment(d, a, b) || onSegment(a, c, d) || onSegment(b, c, d)
    }
    func contains(_ p: InkPoint) -> Bool {
        var inside = false
        for (a, b) in edges {
            if onSegment(p, a, b) { return true }
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }
    func selection(in page: NotePage) -> PageSelection {
        // A tap or a straight drag is not an enclosed region.
        guard points.count >= 3,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              abs(edges.reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }) > 8 else { return PageSelection() }
        let boundary = edges
        var result = PageSelection()
        for stroke in page.strokes {
            if stroke.points.contains(where: contains) || zip(stroke.points, stroke.points.dropFirst()).contains(where: { a, b in
                boundary.contains { intersects(a, b, $0.0, $0.1) }
            }) { result.strokes.insert(stroke.id) }
        }
        for text in page.texts {
            let corners = [InkPoint(x: text.x, y: text.y), InkPoint(x: text.x + 300, y: text.y),
                           InkPoint(x: text.x + 300, y: text.y + 90), InkPoint(x: text.x, y: text.y + 90)]
            let rectangle = CGRect(x: text.x, y: text.y, width: 300, height: 90)
            if corners.contains(where: contains) || points.contains(where: { rectangle.contains(CGPoint(x: $0.x, y: $0.y)) }) ||
                zip(corners, Array(corners.dropFirst()) + [corners[0]]).contains(where: { a, b in
                    boundary.contains { intersects(a, b, $0.0, $0.1) }
                }) { result.texts.insert(text.id) }
        }
        return result
    }
}
