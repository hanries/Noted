import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics
import CoreText
import ImageIO

struct TransferError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.notedNotebook, .pdf, .png, .jpeg] }
    var data: Data
    var name: String
    init(data: Data, name: String) { self.data = data; self.name = name }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data; name = configuration.file.preferredFilename ?? "Notebook"
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents: data); wrapper.preferredFilename = name; return wrapper
    }
}

enum NotebookTransfer {
    static func validate(_ book: Notebook) throws {
        for asset in book.assets ?? [] {
            if asset.kind == .pdf {
                guard let provider = CGDataProvider(data: asset.data as CFData), let pdf = CGPDFDocument(provider),
                      !pdf.isEncrypted, pdf.numberOfPages == asset.pageCount else { throw TransferError(message: "An embedded PDF is damaged or locked. The notebook was not changed.") }
            } else {
                guard let source = CGImageSourceCreateWithData(asset.data as CFData, nil),
                      let type = CGImageSourceGetType(source),
                      type as String == (asset.kind == .png ? UTType.png.identifier : UTType.jpeg.identifier),
                      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw TransferError(message: "An embedded image is damaged. The notebook was not changed.") }
            }
        }
    }

    static func read(_ url: URL) throws -> Notebook {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { actual in
            result = Result { try Data(contentsOf: actual) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        let data = try result.get()
        if url.pathExtension.lowercased() == "noted" { let book = try Notebook.decode(data); try validate(book); return book }
        let asset: NotebookAsset
        if let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider) {
            guard !pdf.isEncrypted, pdf.numberOfPages > 0 else { throw TransferError(message: "This PDF is empty or password-protected. Import an unlocked copy.") }
            asset = NotebookAsset(kind: .pdf, data: data, pageCount: pdf.numberOfPages)
        } else if let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source),
                  [UTType.png.identifier, UTType.jpeg.identifier].contains(type as String),
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil {
            asset = NotebookAsset(kind: type as String == UTType.png.identifier ? .png : .jpeg, data: data, pageCount: 1)
        } else { throw TransferError(message: "Choose a valid Noted notebook, unlocked PDF, PNG, or JPEG image.") }
        return Notebook(version: 2, title: url.deletingPathExtension().lastPathComponent,
                        pages: (0..<asset.pageCount).map { NotePage(paper: .blank, background: PageBackground(assetID: asset.id, page: $0)) }, assets: [asset])
    }
}

// A single renderer keeps exports, imported backgrounds and library previews consistent.
enum NotebookRenderer {
    private static let backgroundCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>(); cache.totalCostLimit = 64 * 1024 * 1024; return cache
    }()
    static func background(_ reference: PageBackground?, assets: [NotebookAsset]) -> CGImage? {
        guard let reference, let asset = assets.first(where: { $0.id == reference.assetID }) else { return nil }
        let key = "\(asset.id)-\(reference.page)" as NSString
        if let image = backgroundCache.object(forKey: key) { return image }
        guard let context = bitmap(width: 1536, height: 2048) else { return nil }
        context.translateBy(x: 0, y: 2048); context.scaleBy(x: 2, y: -2)
        drawBackground(asset, page: reference.page, in: context)
        guard let image = context.makeImage() else { return nil }
        backgroundCache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
    private static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
    static func image(page: NotePage, assets: [NotebookAsset], paper: Bool, scale: Double = 2) -> CGImage? {
        guard let context = bitmap(width: Int(768 * scale), height: Int(1024 * scale)) else { return nil }
        context.translateBy(x: 0, y: 1024 * scale); context.scaleBy(x: scale, y: -scale)
        draw(page: page, assets: assets, paper: paper, in: context)
        return context.makeImage()
    }
    static func imageData(_ image: CGImage, type: UTType) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
    static func pdf(_ book: Notebook, paper: Bool) throws -> Data {
        let data = NSMutableData()
        var rect = CGRect(x: 0, y: 0, width: 768, height: 1024)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &rect, nil) else { throw CocoaError(.fileWriteUnknown) }
        for page in book.pages {
            context.beginPDFPage(nil)
            context.saveGState(); context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1, y: -1)
            draw(page: page, assets: book.assets ?? [], paper: paper, in: context)
            context.restoreGState(); context.endPDFPage()
        }
        context.closePDF(); return data as Data
    }
    private static func color(_ name: String) -> CGColor {
        let colors: [String: [CGFloat]] = ["ink": [0.18, 0.22, 0.23], "green": [0.16, 0.40, 0.31], "blue": [0.22, 0.38, 0.65], "red": [0.72, 0.29, 0.25], "gold": [0.88, 0.68, 0.20]]
        let c = colors[name] ?? colors["ink"]!; return CGColor(red: c[0], green: c[1], blue: c[2], alpha: 1)
    }
    private static func drawBackground(_ asset: NotebookAsset, page: Int, in context: CGContext) {
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: 0, y: 1024); context.scaleBy(x: 1, y: -1)
        let destination = CGRect(x: 0, y: 0, width: 768, height: 1024)
        if asset.kind == .pdf, let provider = CGDataProvider(data: asset.data as CFData), let pdf = CGPDFDocument(provider), let source = pdf.page(at: page + 1) {
            context.concatenate(source.getDrawingTransform(.cropBox, rect: destination, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(source)
        } else if let source = CGImageSourceCreateWithData(asset.data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 8192] as CFDictionary) {
            let scale = min(768 / Double(image.width), 1024 / Double(image.height))
            let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
            context.draw(image, in: CGRect(x: (768-size.width)/2, y: (1024-size.height)/2, width: size.width, height: size.height))
        }
    }
    static func draw(page: NotePage, assets: [NotebookAsset], paper: Bool, in context: CGContext) {
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 768, height: 1024))
        if let background = page.background, let asset = assets.first(where: { $0.id == background.assetID }) { drawBackground(asset, page: background.page, in: context) }
        if paper && page.paper != .blank {
            context.setStrokeColor(CGColor(gray: 0.5, alpha: 0.17)); context.setLineWidth(0.6)
            let step = page.paper == .grid ? 24 : 32
            for y in stride(from: 64, through: 992, by: step) { context.move(to: CGPoint(x: 40, y: y)); context.addLine(to: CGPoint(x: 728, y: y)) }
            if page.paper == .grid { for x in stride(from: 40, through: 728, by: 24) { context.move(to: CGPoint(x: x, y: 64)); context.addLine(to: CGPoint(x: x, y: 992)) } }
            context.strokePath()
        }
        for stroke in page.strokes {
            context.saveGState(); context.setAlpha(stroke.isHighlighter ? 0.28 : 1); context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setStrokeColor(color(stroke.color)); context.setFillColor(color(stroke.color)); context.setLineCap(.round)
            if stroke.points.count == 1, let p = stroke.points.first { context.fillEllipse(in: CGRect(x: p.x-stroke.width/2, y: p.y-stroke.width/2, width: stroke.width, height: stroke.width)) }
            for (a,b) in zip(stroke.points, stroke.points.dropFirst()) {
                context.setLineWidth(stroke.width * (stroke.isHighlighter ? 1 : 0.45 + 0.55 * (a.pressure+b.pressure)/2))
                context.move(to: CGPoint(x: a.x, y: a.y)); context.addLine(to: CGPoint(x: b.x, y: b.y)); context.strokePath()
            }
            context.endTransparencyLayer(); context.restoreGState()
        }
        for text in page.texts {
            context.saveGState(); context.translateBy(x: text.x, y: text.y + 90); context.scaleBy(x: 1, y: -1); context.textMatrix = .identity
            let font = CTFontCreateUIFontForLanguage(.system, 20, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 20, nil)
            let string = NSAttributedString(string: text.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color("ink")])
            let setter = CTFramesetterCreateWithAttributedString(string)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: CGRect(x: 0,y: 0,width: 300,height: 90), transform: nil), nil)
            CTFrameDraw(frame, context); context.restoreGState()
        }
    }
}
