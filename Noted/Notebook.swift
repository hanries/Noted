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
    var pencil: Bool? = nil

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
    var boxWidth: Double? = nil
    var boxHeight: Double? = nil
    var fontSize: Double? = nil
    var width: Double { boxWidth ?? 300 }
    var height: Double { boxHeight ?? 90 }
    var size: Double { fontSize ?? 20 }
    var bounds: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct PlacedImage: Codable, Identifiable, Equatable {
    var id = UUID()
    var assetID: UUID
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var bounds: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

enum Paper: String, Codable, CaseIterable {
    case ruled = "Ruled", grid = "Grid", blank = "Blank"
}

struct NotePage: Codable, Identifiable, Equatable {
    var id = UUID()
    var paper: Paper = .ruled
    var strokes: [InkStroke] = []
    var texts: [TextCard] = []
    var background: PageBackground? = nil
    var images: [PlacedImage]? = nil
}

struct Notebook: Codable, Equatable {
    var version = 1
    var title = "Untitled notebook"
    var pages: [NotePage] = [NotePage()]
    var assets: [NotebookAsset]? = nil

    static func decode(_ data: Data) throws -> Notebook {
        let book = try JSONDecoder().decode(Notebook.self, from: data)
        guard (1...3).contains(book.version), !book.pages.isEmpty,
              Set(book.pages.map(\.id)).count == book.pages.count else { throw NotebookError.invalidFormat }
        let assets = book.assets ?? []
        guard Set(assets.map(\.id)).count == assets.count,
              assets.allSatisfy({ !$0.data.isEmpty && $0.pageCount > 0 && ($0.kind == .pdf || $0.pageCount == 1) }),
              book.version >= 2 || (assets.isEmpty && book.pages.allSatisfy { $0.background == nil }) else { throw NotebookError.invalidFormat }
        for page in book.pages {
            guard book.version >= 3 || (!page.usesModernObjects) else { throw NotebookError.invalidFormat }
            let images = page.images ?? []
            guard Set(images.map(\.id)).count == images.count,
                  images.allSatisfy({ item in
                      item.x.isFinite && item.y.isFinite && item.width.isFinite && item.height.isFinite &&
                      item.width > 0 && item.width <= 768 && item.height > 0 && item.height <= 1024 &&
                      assets.contains { $0.id == item.assetID && $0.kind != .pdf }
                  }) else { throw NotebookError.invalidFormat }
            if let background = page.background {
                guard let asset = assets.first(where: { $0.id == background.assetID }),
                      (0..<asset.pageCount).contains(background.page) else { throw NotebookError.invalidFormat }
            }
            guard Set(page.strokes.map(\.id)).count == page.strokes.count,
                  Set(page.texts.map(\.id)).count == page.texts.count,
                  page.strokes.allSatisfy({ stroke in
                      stroke.width.isFinite && stroke.width > 0 && stroke.width <= 100 &&
                      stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.pressure.isFinite && $0.pressure >= 0 && $0.pressure <= 1 }
                  }), page.texts.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.width.isFinite && $0.width > 0 && $0.width <= 768 && $0.height.isFinite && $0.height > 0 && $0.height <= 1024 && $0.size.isFinite && (1...200).contains($0.size) }) else { throw NotebookError.invalidFormat }
        }
        return book
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var copy = self
        if version == 1 && (!(assets ?? []).isEmpty || pages.contains(where: { $0.background != nil })) { copy.version = 2 }
        if (1...2).contains(version) && pages.contains(where: \.usesModernObjects) { copy.version = 3 }
        return try encoder.encode(copy)
    }
}

enum NotebookError: Error { case invalidFormat }

// Viewport state never enters the document or undo history.
struct NotebookViewport: Equatable {
    static let minimumZoom = 0.4
    static let maximumZoom = 4.0
    static let pageGap = 12.0
    var zoom: Double = 1
    var offset: CGSize = .zero
    var pageCount = 1

    func scale(in size: CGSize) -> Double {
        max(0.1, min((size.width - 44) / 768, (size.height - 44) / 1024)) * zoom
    }
    private func restingOrigin(in size: CGSize) -> CGPoint {
        let s = scale(in: size)
        return CGPoint(x: (size.width - 768 * s) / 2,
                       y: pageCount > 1 ? 22 : (size.height - 1024 * s) / 2)
    }
    func origin(in size: CGSize) -> CGPoint {
        let resting = restingOrigin(in: size)
        return CGPoint(x: resting.x + offset.width, y: resting.y + offset.height)
    }
    func pagePoint(_ point: InkPoint, in size: CGSize) -> InkPoint {
        let o = origin(in: size), s = scale(in: size)
        return InkPoint(x: (point.x - o.x) / s, y: (point.y - o.y) / s, pressure: point.pressure)
    }
    func pageStride(in size: CGSize) -> Double { 1024 * scale(in: size) + Self.pageGap }
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
        let nextZoom = min(Self.maximumZoom, max(Self.minimumZoom, zoom * factor))
        guard nextZoom != zoom else { return }
        let oldOrigin = origin(in: size)
        let anchoredPage = max(0, min(pageCount - 1, Int(floor((anchor.y - oldOrigin.y) / pageStride(in: size)))))
        let p = pagePoint(InkPoint(x: anchor.x, y: anchor.y), at: anchoredPage, in: size)
        zoom = nextZoom
        let s = scale(in: size), resting = restingOrigin(in: size)
        offset = CGSize(width: anchor.x - p.x * s - resting.x,
                        height: anchor.y - p.y * s - Double(anchoredPage) * pageStride(in: size) - resting.y)
        clamp(in: size)
    }
    mutating func clamp(in size: CGSize) {
        let s = scale(in: size)
        let x = max(0, (768 * s - size.width) / 2 + 22)
        let restingY = restingOrigin(in: size).y
        let totalHeight = 1024 * s + Double(max(0, pageCount - 1)) * pageStride(in: size)
        let minimumY = min(0, size.height - 22 - restingY - totalHeight)
        let maximumY = max(0, 22 - restingY)
        offset.width = min(x, max(-x, offset.width))
        offset.height = min(maximumY, max(minimumY, offset.height))
    }
}

extension Notebook {
    // Only creation uses this factory; reading existing files never adds blank pages.
    static func newNotebook(title: String = "Untitled notebook", paper: Paper = .ruled) -> Notebook {
        Notebook(title: title, pages: (0..<10).map { _ in NotePage(paper: paper) })
    }
    @discardableResult
    mutating func appendPageAfterScroll(after pageID: UUID) -> Bool {
        guard let last = pages.last, last.id == pageID else { return false }
        pages.append(NotePage(paper: last.paper)); return true
    }
}


extension NotePage {
    func text(at point: InkPoint) -> TextCard? {
        texts.last { $0.bounds.contains(CGPoint(x: point.x, y: point.y)) }
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
    var images: Set<UUID> = []
    var count: Int { strokes.count + texts.count + images.count }

    func bounds(in page: NotePage) -> CGRect? {
        var result = CGRect.null
        for stroke in page.strokes where strokes.contains(stroke.id) {
            for point in stroke.points {
                result = result.union(CGRect(x: point.x - stroke.width / 2, y: point.y - stroke.width / 2,
                                             width: stroke.width, height: stroke.width))
            }
        }
        for text in page.texts where texts.contains(text.id) {
            result = result.union(text.bounds)
        }
        for image in page.images ?? [] where images.contains(image.id) { result = result.union(image.bounds) }
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
        if var items = moved.images {
            for i in items.indices where images.contains(items[i].id) { items[i].x += dx; items[i].y += dy }
            moved.images = items
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
            let corners = [InkPoint(x: text.x, y: text.y), InkPoint(x: text.x + text.width, y: text.y),
                           InkPoint(x: text.x + text.width, y: text.y + text.height), InkPoint(x: text.x, y: text.y + text.height)]
            let rectangle = text.bounds
            if corners.contains(where: contains) || points.contains(where: { rectangle.contains(CGPoint(x: $0.x, y: $0.y)) }) ||
                zip(corners, Array(corners.dropFirst()) + [corners[0]]).contains(where: { a, b in
                    boundary.contains { intersects(a, b, $0.0, $0.1) }
                }) { result.texts.insert(text.id) }
        }
        for image in page.images ?? [] {
            let r = image.bounds
            let corners = [InkPoint(x: r.minX, y: r.minY), InkPoint(x: r.maxX, y: r.minY), InkPoint(x: r.maxX, y: r.maxY), InkPoint(x: r.minX, y: r.maxY)]
            if corners.contains(where: contains) || points.contains(where: { r.contains(CGPoint(x: $0.x, y: $0.y)) }) ||
                zip(corners, Array(corners.dropFirst()) + [corners[0]]).contains(where: { a, b in boundary.contains { intersects(a, b, $0.0, $0.1) } }) { result.images.insert(image.id) }
        }
        return result
    }
}


struct NotebookAsset: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case pdf, png, jpeg }
    var id = UUID()
    var kind: Kind
    var data: Data
    var pageCount: Int
}

struct PageBackground: Codable, Equatable {
    var assetID: UUID
    var page: Int = 0
}

extension Notebook {
    func selectingPages(_ indices: [Int]) -> Notebook {
        var copy = self
        copy.pages = indices.filter { pages.indices.contains($0) }.map { pages[$0] }
        let used = Set(copy.pages.compactMap { $0.background?.assetID } + copy.pages.flatMap { ($0.images ?? []).map(\.assetID) })
        copy.assets = assets?.filter { used.contains($0.id) }
        return copy
    }
    mutating func appendImported(_ imported: Notebook) {
        var assetIDs: [UUID: UUID] = [:]
        let copiedAssets = (imported.assets ?? []).map { original in
            var asset = original; asset.id = UUID(); assetIDs[original.id] = asset.id; return asset
        }
        if !copiedAssets.isEmpty { assets = (assets ?? []) + copiedAssets; version = max(version, imported.version, 2) }
        pages += imported.pages.map { original in
            var page = original; page.id = UUID()
            if let id = page.background?.assetID { page.background?.assetID = assetIDs[id] ?? id }
            page.images = page.images?.map { original in var image = original; image.assetID = assetIDs[image.assetID] ?? image.assetID; return image }
            return page
        }
    }
}

// Page numbers entered by the user are one-based; internal indices are zero-based.
enum PageRange {
    static func parse(_ text: String, count: Int) throws -> [Int] {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Array(0..<count) }
        var result = Set<Int>()
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let ends = part.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard (1...2).contains(ends.count), let first = Int(ends[0]), first >= 1, first <= count,
                  let last = Int(ends.last!), last >= first, last <= count else { throw NotebookError.invalidFormat }
            result.formUnion((first...last).map { $0 - 1 })
        }
        guard !result.isEmpty else { throw NotebookError.invalidFormat }
        return result.sorted()
    }
}


extension NotePage {
    var usesModernObjects: Bool {
        !(images ?? []).isEmpty || strokes.contains { $0.pencil != nil } || texts.contains { $0.boxWidth != nil || $0.boxHeight != nil || $0.fontSize != nil }
    }
}

extension PageSelection {
    static func rectangle(from a: InkPoint, to b: InkPoint, in page: NotePage) -> PageSelection {
        LassoRegion(points: [a, InkPoint(x: b.x, y: a.y), b, InkPoint(x: a.x, y: b.y)]).selection(in: page)
    }
    func removing(from page: NotePage) -> NotePage {
        var copy = page
        copy.strokes.removeAll { strokes.contains($0.id) }
        copy.texts.removeAll { texts.contains($0.id) }
        copy.images?.removeAll { images.contains($0.id) }
        return copy
    }
    func contents(of page: NotePage) -> NotePage {
        NotePage(paper: .blank, strokes: page.strokes.filter { strokes.contains($0.id) }, texts: page.texts.filter { texts.contains($0.id) }, images: page.images?.filter { images.contains($0.id) })
    }
    func resizing(_ page: NotePage, to point: InkPoint) -> NotePage {
        guard let r = bounds(in: page), r.width > 0, r.height > 0 else { return page }
        var copy = page
        if count == 1, let index = page.texts.firstIndex(where: { texts.contains($0.id) }) {
            copy.texts[index].boxWidth = max(44, min(768 - r.minX, point.x - r.minX))
            copy.texts[index].boxHeight = max(44, min(1024 - r.minY, point.y - r.minY))
            return copy
        }
        // Project onto the box diagonal so either horizontal or vertical pulls resize.
        let diagonalSquared = r.width*r.width + r.height*r.height
        var factor = max(0.1, ((point.x-r.minX)*r.width + (point.y-r.minY)*r.height)/diagonalSquared)
        factor = min(factor, (768-r.minX)/r.width, (1024-r.minY)/r.height)
        for text in page.texts where texts.contains(text.id) { factor = min(factor, 200/text.size); factor = max(factor, 1/text.size) }
        for stroke in page.strokes where strokes.contains(stroke.id) { factor = min(factor, 100/stroke.width) }
        guard factor > 0 && factor.isFinite else { return page }
        for i in copy.strokes.indices where strokes.contains(copy.strokes[i].id) {
            copy.strokes[i].points = page.strokes[i].points.map { InkPoint(x: r.minX + ($0.x-r.minX)*factor, y: r.minY + ($0.y-r.minY)*factor, pressure: $0.pressure) }
            copy.strokes[i].width *= factor
        }
        for i in copy.texts.indices where texts.contains(copy.texts[i].id) {
            let t = page.texts[i]
            copy.texts[i].x = r.minX + (t.x-r.minX)*factor; copy.texts[i].y = r.minY + (t.y-r.minY)*factor
            copy.texts[i].boxWidth = t.width*factor; copy.texts[i].boxHeight = t.height*factor; copy.texts[i].fontSize = t.size*factor
        }
        if var items = copy.images {
            for i in items.indices where images.contains(items[i].id) {
                items[i].x = r.minX + (items[i].x-r.minX)*factor; items[i].y = r.minY + (items[i].y-r.minY)*factor
                items[i].width *= factor; items[i].height *= factor
            }
            copy.images = items
        }
        return copy
    }
}

extension InkStroke {
    // Clip each segment against the eraser circle, retaining interpolated pressure.
    func erasing(at center: InkPoint, radius: Double) -> [InkStroke] {
        guard distance(to: center) <= radius + width/2 else { return [self] }
        let radius = radius + width/2
        if points.count == 1 { return [] }
        var fragments: [[InkPoint]] = [], run: [InkPoint] = []
        func point(_ a: InkPoint, _ b: InkPoint, _ t: Double) -> InkPoint {
            InkPoint(x: a.x+(b.x-a.x)*t, y: a.y+(b.y-a.y)*t, pressure: a.pressure+(b.pressure-a.pressure)*t)
        }
        func flush() { if run.count >= 2 { fragments.append(run) }; run = [] }
        for (a,b) in zip(points, points.dropFirst()) {
            let dx = b.x-a.x, dy = b.y-a.y, fx = a.x-center.x, fy = a.y-center.y
            let aa = dx*dx+dy*dy, bb = 2*(fx*dx+fy*dy), cc = fx*fx+fy*fy-radius*radius
            var cuts = [0.0, 1.0]
            let discriminant = bb*bb-4*aa*cc
            if aa > 0 && discriminant > 0 {
                for t in [(-bb-sqrt(discriminant))/(2*aa), (-bb+sqrt(discriminant))/(2*aa)] where t > 0 && t < 1 { cuts.append(t) }
            }
            cuts.sort()
            for (lo,hi) in zip(cuts, cuts.dropFirst()) {
                let mid = point(a,b,(lo+hi)/2)
                if hypot(mid.x-center.x,mid.y-center.y) >= radius {
                    let start = point(a,b,lo), end = point(a,b,hi)
                    if let last = run.last, hypot(last.x-start.x,last.y-start.y) > 0.0001 { flush() }
                    if run.isEmpty { run.append(start) }; run.append(end)
                } else { flush() }
            }
        }
        flush()
        return fragments.enumerated().map { index, points in
            var copy = self; copy.points = points; if index > 0 { copy.id = UUID() }; return copy
        }
    }
}
