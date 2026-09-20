import SwiftUI
import UniformTypeIdentifiers

struct NotebookImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    var allowNotebooks = true
    var onImport: (Notebook) throws -> Void
    @State private var choosing = false
    @State private var imported: Notebook?
    @State private var range = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Import a PDF or image as pages you can write on. A Noted file keeps its editable ink and text.").foregroundStyle(.secondary)
                Button("Choose file…") { choosing = true }.buttonStyle(.borderedProminent).disabled(busy)
                if busy { ProgressView("Reading file…") }
                if let imported {
                    Text(imported.title).font(.headline)
                    Text("\(imported.pages.count) pages")
                    TextField("Pages: all, or 1-3, 5", text: $range).textFieldStyle(.roundedBorder)
                    Text("Leave blank for all pages. PDF and image content becomes a background; new writing stays editable.").font(.caption).foregroundStyle(.secondary)
                    if let first = try? PageRange.parse(range, count: imported.pages.count).first {
                        PaperCanvas(page: imported.pages[first], pending: nil, selection: nil, erased: [], assets: imported.assets ?? [])
                            .frame(width: 150, height: 200).border(.gray.opacity(0.3))
                    }
                    Button("Import pages") {
                        do {
                            let indices = try PageRange.parse(range, count: imported.pages.count)
                            try onImport(imported.selectingPages(indices)); dismiss()
                        } catch { self.error = "Couldn’t import: \(error.localizedDescription) Check the page range and available storage." }
                    }.buttonStyle(.borderedProminent)
                }
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
                Spacer(minLength: 0)
            }.padding(24).frame(minWidth: 300, idealWidth: 480, minHeight: 440)
                .navigationTitle("Import")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: allowNotebooks ? [.notedNotebook, .pdf, .png, .jpeg] : [.pdf, .png, .jpeg]) { result in
            guard case .success(let url) = result else {
                if case .failure(let error) = result { self.error = error.localizedDescription }; return
            }
            busy = true; error = nil; imported = nil
            Task {
                do { imported = try await Task.detached { try NotebookTransfer.read(url) }.value; range = "" }
                catch { self.error = error.localizedDescription }
                busy = false
            }
        }
    }
}

struct NotebookExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let notebook: Notebook
    @AppStorage("exportFormat") private var format = "PDF"
    @State private var range = ""
    @State private var includePaper = true
    @State private var busy = false
    @State private var error: String?
    @State private var files: [ExportFile] = []
    @State private var showSingle = false
    @State private var showMultiple = false
    private var type: UTType { switch format { case "PDF": .pdf; case "PNG": .png; case "JPEG": .jpeg; default: .notedNotebook } }
    private var indices: [Int]? { try? PageRange.parse(range, count: notebook.pages.count) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Format", selection: $format) { ForEach(["Noted", "PDF", "PNG", "JPEG"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    Text(format == "Noted" ? "Editable notebook, including imported backgrounds." : "A shareable copy. Keep your Noted file to continue editing the original handwriting.").foregroundStyle(.secondary)
                    TextField("Pages: all, or 1-3, 5", text: $range).textFieldStyle(.roundedBorder)
                    if format != "Noted" { Toggle("Include ruled / grid paper", isOn: $includePaper) }
                    if let indices, let first = indices.first {
                        Text("\(indices.count) pages selected").font(.caption)
                        ExportPreview(page: notebook.pages[first], assets: notebook.assets ?? [], includePaper: format == "Noted" || includePaper)
                    } else { Text("Enter valid page numbers between 1 and \(notebook.pages.count).").foregroundStyle(.red) }
                    if busy { ProgressView("Preparing export…") }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("Save a copy…", action: prepare).buttonStyle(.borderedProminent).disabled(indices == nil || busy)
                    Text("Exporting doesn’t change where your working notebook is saved.").font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.frame(minWidth: 320, idealWidth: 500, minHeight: 490)
                .navigationTitle("Export")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) } }
                .disabled(busy)
        }
        .fileExporter(isPresented: $showSingle, document: files.first, contentType: type, defaultFilename: files.first?.name) { result in
            if case .failure(let error) = result { self.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $showMultiple, documents: files, contentType: type) { result in
            if case .failure(let error) = result { self.error = error.localizedDescription }
        }
    }
    private func prepare() {
        guard let indices else { return }
        let selected = notebook.selectingPages(indices), exportType = type, paper = includePaper
        busy = true; error = nil
        Task {
            do {
                files = try await Task.detached {
                    let title = selected.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                    if exportType == .notedNotebook { return [ExportFile(data: try selected.encoded(), name: title + " copy.noted")] }
                    if exportType == .pdf { return [ExportFile(data: try NotebookRenderer.pdf(selected, paper: paper), name: title + ".pdf")] }
                    return try selected.pages.enumerated().map { offset, page in
                        guard let image = NotebookRenderer.image(page: page, assets: selected.assets ?? [], paper: paper) else { throw CocoaError(.fileWriteUnknown) }
                        return ExportFile(data: try NotebookRenderer.imageData(image, type: exportType), name: "\(title)-page-\(indices[offset]+1).\(exportType == .png ? "png" : "jpg")")
                    }
                }.value
                busy = false
                if files.count == 1 { showSingle = true } else { showMultiple = true }
            } catch { self.error = error.localizedDescription; busy = false }
        }
    }
}

private struct ExportPreview: View {
    var page: NotePage
    var assets: [NotebookAsset]
    var includePaper: Bool
    var body: some View {
        var preview = page
        if !includePaper { preview.paper = .blank }
        return PaperCanvas(page: preview, pending: nil, selection: nil, erased: [], assets: assets)
            .frame(width: 180, height: 240).border(.gray.opacity(0.3))
    }
}
