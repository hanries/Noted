import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO
extension UTType { static let notedNotebook = UTType(exportedAs: "app.noted.notebook", conformingTo: .json) }
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: " + message) }
    print("PASS: " + message)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var book = Notebook(title: "Transfer check", pages: [NotePage(paper: .grid), NotePage(paper: .ruled)])
book.pages[0].texts = [TextCard(text: "Top left\nPDF / image check", x: 60, y: 70)]
book.pages[0].strokes = [InkStroke(points: [InkPoint(x: 80, y: 300, pressure: 0.2), InkPoint(x: 650, y: 350, pressure: 1)], color: "blue", width: 10)]
book.pages[1].texts = [TextCard(text: "Second page", x: 60, y: 80)]
let pdf = try NotebookRenderer.pdf(book, paper: true)
let pdfURL = folder.appendingPathComponent("Two pages.pdf"); try pdf.write(to: pdfURL)
let loadedPDF = CGPDFDocument(CGDataProvider(data: pdf as CFData)!)!
check(loadedPDF.numberOfPages == 2, "PDF export preserves page count")
let importedPDF = try NotebookTransfer.read(pdfURL)
check(importedPDF.version == 2 && importedPDF.pages.count == 2 && importedPDF.assets?.count == 1, "PDF import embeds one asset with multiple page references")
var annotated = importedPDF
annotated.pages[1].texts = [TextCard(text: "Editable annotation", x: 100, y: 400)]
let notedURL = folder.appendingPathComponent("Imported.noted"); try annotated.encoded().write(to: notedURL)
check((try? NotebookTransfer.read(notedURL)) == annotated, "Embedded PDF and editable annotations survive Noted export/import")
let reexported = try NotebookRenderer.pdf(annotated, paper: true)
try reexported.write(to: folder.appendingPathComponent("Annotated.pdf"))
check(CGPDFDocument(CGDataProvider(data: reexported as CFData)!)?.numberOfPages == 2, "Annotated PDF exports both background pages")
for type in [UTType.png, .jpeg] {
    let image = NotebookRenderer.image(page: book.pages[0], assets: [], paper: false)!
    let data = try NotebookRenderer.imageData(image, type: type)
    let url = folder.appendingPathComponent("Page.\(type == .png ? "png" : "jpg")"); try data.write(to: url)
    let imported = try NotebookTransfer.read(url)
    check(imported.pages.count == 1 && imported.assets?.first?.pageCount == 1, "\(type.identifier) imports as an embedded background")
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let reopened = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    check(reopened.width == 1536 && reopened.height == 2048, "\(type.identifier) export has expected page resolution")
}
let selected = annotated.selectingPages([1])
let selectedPDF = try NotebookRenderer.pdf(selected, paper: false)
check(CGPDFDocument(CGDataProvider(data: selectedPDF as CFData)!)?.numberOfPages == 1 && selected.pages[0].background?.page == 1, "Selected-page export keeps the correct imported PDF page")
let rendered = NotebookRenderer.image(page: annotated.pages[1], assets: annotated.assets ?? [], paper: true)!
try NotebookRenderer.imageData(rendered, type: .png).write(to: folder.appendingPathComponent("Preview.png"))
let invalidURL = folder.appendingPathComponent("Broken.pdf"); try Data("not a PDF".utf8).write(to: invalidURL)
check((try? NotebookTransfer.read(invalidURL)) == nil, "Corrupt imports fail without creating blank notebooks")
var broken = annotated; broken.assets![0].data = Data([1,2,3])
check((try? NotebookTransfer.validate(broken)) == nil, "Corrupt embedded media fails validation")

let photoData = try Data(contentsOf: folder.appendingPathComponent("Page.jpg"))
let normalized = try NotebookTransfer.photo(photoData)
check(normalized.kind == .png && NotebookRenderer.objectImage(normalized) != nil, "Photo insertion normalizes image data into a portable embedded asset")
let photo = PlacedImage(assetID: normalized.id, x: 100, y: 120, width: 240, height: 320)
let pencilStroke = InkStroke(points: [InkPoint(x: 60, y: 600, pressure: 0.2), InkPoint(x: 450, y: 620, pressure: 1)], color: "purple", width: 6, pencil: true)
let flexibleText = TextCard(text: "Movable image and soft pencil\nEditable on either device", x: 80, y: 700, boxWidth: 410, boxHeight: 120, fontSize: 26)
let editingBook = Notebook(version: 3, title: "Editor checkpoint", pages: [NotePage(strokes: [pencilStroke], texts: [flexibleText], images: [photo])], assets: [normalized])
let editingURL = folder.appendingPathComponent("Editor checkpoint.noted"); try editingBook.encoded().write(to: editingURL)
check((try? NotebookTransfer.read(editingURL)) == editingBook, "Native version 3 reading preserves Pencil, flexible text and placed images")
let editorPDF = try NotebookRenderer.pdf(editingBook, paper: true)
try editorPDF.write(to: folder.appendingPathComponent("Editor checkpoint.pdf"))
check(CGPDFDocument(CGDataProvider(data: editorPDF as CFData)!)?.numberOfPages == 1, "PDF export accepts mixed editable version 3 content")
let editorImage = NotebookRenderer.image(page: editingBook.pages[0], assets: editingBook.assets!, paper: true)!
try NotebookRenderer.imageData(editorImage, type: .png).write(to: folder.appendingPathComponent("Editor checkpoint.png"))
check(editorImage.width == 1536 && editorImage.height == 2048, "Placed-image and Pencil raster export retains page resolution")
let longText = String(repeating: "A longer paragraph wraps naturally. ", count: 12)
check(NotebookRenderer.textHeight(longText, width: 150, fontSize: 20) > NotebookRenderer.textHeight(longText, width: 400, fontSize: 20), "Text layout grows when its wrapping width narrows")
