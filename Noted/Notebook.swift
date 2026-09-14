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
    var text = "New text"
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
    mutating func pan(_ delta: CGSize, in size: CGSize) {
        offset.width += delta.width; offset.height += delta.height; clamp(in: size)
    }
    mutating func magnify(_ factor: Double, at anchor: CGPoint, in size: CGSize) {
        guard factor.isFinite, factor > 0 else { return }
        let p = pagePoint(InkPoint(x: anchor.x, y: anchor.y), in: size)
        zoom = min(4, max(1, zoom * factor))
        let s = scale(in: size)
        offset = CGSize(width: anchor.x - p.x * s - (size.width - 768 * s) / 2,
                        height: anchor.y - p.y * s - (size.height - 1024 * s) / 2)
        clamp(in: size)
    }
    mutating func clamp(in size: CGSize) {
        let s = scale(in: size)
        let x = max(0, (768 * s - size.width) / 2 + 22)
        let y = max(0, (1024 * s - size.height) / 2 + 22)
        offset.width = min(x, max(-x, offset.width)); offset.height = min(y, max(-y, offset.height))
    }
}

extension Notebook {
    @discardableResult
    mutating func appendContinuationPage(after pageID: UUID) -> Bool {
        guard let last = pages.last, last.id == pageID,
              !last.strokes.isEmpty || last.texts.contains(where: { !$0.text.isEmpty }) else { return false }
        pages.append(NotePage(paper: last.paper)); return true
    }
}
