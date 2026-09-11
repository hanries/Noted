import Foundation

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
