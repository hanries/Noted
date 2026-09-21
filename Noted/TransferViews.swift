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
    @State private var pageMode = ExportPageMode.all
    @State private var firstPage = 1
    @State private var lastPage: Int
    @State private var includePaper = true
    @State private var busy = false
    @State private var error: String?
    @State private var files: [ExportFile] = []
    @State private var share: NotebookShare?
    @State private var shareDirectory: URL?
    @State private var showSingle = false
    @State private var showMultiple = false

    init(notebook: Notebook) {
        self.notebook = notebook
        _lastPage = State(initialValue: max(1, notebook.pages.count))
    }

    private var type: UTType { switch format { case "PDF": .pdf; case "PNG": .png; case "JPEG": .jpeg; default: .notedNotebook } }
    private var indices: [Int] {
        guard !notebook.pages.isEmpty else { return [] }
        let first = max(1, min(firstPage, notebook.pages.count))
        let last = max(first, min(lastPage, notebook.pages.count))
        switch pageMode {
        case .all: return Array(notebook.pages.indices)
        case .single: return [first - 1]
        case .range: return Array((first - 1)...(last - 1))
        }
    }
    private var previewIncludesPaper: Bool { format == "Noted" || includePaper }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Format", selection: $format) { ForEach(["Noted", "PDF", "PNG", "JPEG"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    Text(format == "Noted" ? "Editable notebook, including imported backgrounds." : "A shareable copy. Keep your Noted file to continue editing the original handwriting.").foregroundStyle(.secondary)
                    Picker("Pages", selection: $pageMode) {
                        ForEach(ExportPageMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if !notebook.pages.isEmpty {
                        if pageMode == .single {
                            pageSlider("Page", value: $firstPage)
                        } else if pageMode == .range {
                            pageSlider("Starting page", value: Binding(get: { firstPage }, set: { firstPage = $0; lastPage = max(lastPage, $0) }))
                            pageSlider("Ending page", value: Binding(get: { lastPage }, set: { lastPage = $0; firstPage = min(firstPage, $0) }))
                        }
                        HStack(alignment: .top, spacing: 28) {
                            if let first = indices.first {
                                pagePreview(first, label: indices.count > 1 ? "Starting page" : "Page")
                            }
                            if indices.count > 1, let last = indices.last { pagePreview(last, label: "Ending page") }
                        }.frame(maxWidth: .infinity)
                        Text(indices.count == 1 ? "1 page selected" : "\(indices.count) pages selected").font(.caption).foregroundStyle(.secondary)
                    }
                    if format != "Noted" { Toggle("Include ruled / grid paper", isOn: $includePaper) }
                    if busy { ProgressView("Preparing export…") }
                    if let error { Text(error).foregroundStyle(.red) }
                    HStack {
                        Button { prepare(forSharing: true) } label: { Label("Share…", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                            #if os(macOS)
                            .background(MacNotebookSharePresenter(share: share, completion: finishSharing))
                            #endif
                        #if os(macOS)
                        Button("Save a copy…") { prepare(forSharing: false) }.buttonStyle(.bordered)
                        #endif
                    }.disabled(indices.isEmpty || busy || share != nil)
                    Text("Exporting doesn’t change where your working notebook is saved.").font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.frame(minWidth: 320, idealWidth: 520, minHeight: 490)
                .navigationTitle("Export")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy || share != nil) } }
                .disabled(busy)
        }
        .interactiveDismissDisabled(busy || share != nil)
        .onChange(of: pageMode) { _, _ in lastPage = max(firstPage, lastPage) }
        #if os(iOS)
        .sheet(item: $share, onDismiss: removeShareFiles) { payload in
            NotebookActivitySheet(urls: payload.urls) { message in finishSharing(message) }
        }
        #else
        .fileExporter(isPresented: $showSingle, document: files.first, contentType: type, defaultFilename: files.first?.name) { result in
            if case .failure(let error) = result { self.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $showMultiple, documents: files, contentType: type) { result in
            if case .failure(let error) = result { self.error = error.localizedDescription }
        }
        #endif
    }

    private func pageSlider(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(value.wrappedValue) / \(notebook.pages.count)").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                   in: 1...Double(max(2, notebook.pages.count)), step: 1)
                .disabled(notebook.pages.count < 2)
                .accessibilityLabel(title)
                .accessibilityValue("Page \(value.wrappedValue) of \(notebook.pages.count)")
        }
    }

    private func pagePreview(_ index: Int, label: String) -> some View {
        VStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            ExportPreview(page: notebook.pages[index], assets: notebook.assets ?? [], includePaper: previewIncludesPaper, width: 116)
            Text("\(index + 1)").font(.subheadline).monospacedDigit()
        }
    }

    private func prepare(forSharing: Bool) {
        guard !indices.isEmpty else { return }
        let indices = indices, selected = notebook.selectingPages(indices), exportType = type, paper = includePaper
        busy = true; error = nil
        Task {
            do {
                let prepared = try await Task.detached {
                    let unsafeCharacters = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))
                    let cleanTitle = selected.title.components(separatedBy: unsafeCharacters).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
                    var title = cleanTitle.isEmpty ? "Notebook" : String(cleanTitle.prefix(100))
                    // Filesystem name limits are measured in bytes, including multibyte characters.
                    while title.utf8.count > 180 { title.removeLast() }
                    let output: [ExportFile]
                    if exportType == .notedNotebook { output = [ExportFile(data: try selected.encoded(), name: title + " copy.noted")] }
                    else if exportType == .pdf { output = [ExportFile(data: try NotebookRenderer.pdf(selected, paper: paper), name: title + ".pdf")] }
                    else {
                        output = try selected.pages.enumerated().map { offset, page in
                            guard let image = NotebookRenderer.image(page: page, assets: selected.assets ?? [], paper: paper) else { throw CocoaError(.fileWriteUnknown) }
                            return ExportFile(data: try NotebookRenderer.imageData(image, type: exportType), name: "\(title)-page-\(indices[offset]+1).\(exportType == .png ? "png" : "jpg")")
                        }
                    }
                    return (output, forSharing ? try NotebookShare(files: output) : nil)
                }.value
                files = prepared.0; busy = false
                if let payload = prepared.1 { shareDirectory = payload.directory; share = payload }
                else if files.count == 1 { showSingle = true } else { showMultiple = true }
            } catch { self.error = error.localizedDescription; busy = false }
        }
    }

    private func finishSharing(_ message: String?) {
        if let message { error = message }
        share = nil
        #if os(macOS)
        removeShareFiles()
        #endif
    }

    private func removeShareFiles() {
        if let directory = shareDirectory { try? FileManager.default.removeItem(at: directory) }
        shareDirectory = nil
    }
}

private enum ExportPageMode: String, CaseIterable, Identifiable {
    case all = "All pages", range = "Page range", single = "Single page"
    var id: String { rawValue }
}

/// A separate, immutable export snapshot survives until the native share activity finishes.
private struct NotebookShare: Identifiable {
    let id = UUID()
    let directory: URL
    let urls: [URL]

    init(files: [ExportFile]) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotedExports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Interrupted app sessions may leave snapshots behind. Never purge a recent/active export.
        let staleBefore = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            if let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate, created < staleBefore {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var urls: [URL] = []
            for file in files {
                let url = directory.appendingPathComponent(file.name)
                try file.data.write(to: url, options: .atomic)
                urls.append(url)
            }
            self.directory = directory; self.urls = urls
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

#if os(iOS)
import UIKit

private struct NotebookActivitySheet: UIViewControllerRepresentable {
    let urls: [URL]
    var completion: (String?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, error in
            DispatchQueue.main.async { completion(error?.localizedDescription) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#else
import AppKit

private struct MacNotebookSharePresenter: NSViewRepresentable {
    let share: NotebookShare?
    var completion: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.completion = completion
        guard let share, context.coordinator.presentedID != share.id else { return }
        context.coordinator.presentedID = share.id
        DispatchQueue.main.async {
            guard view.window != nil else { context.coordinator.finish("Couldn’t open sharing. Try Share again."); return }
            let picker = NSSharingServicePicker(items: share.urls)
            context.coordinator.picker = picker
            picker.delegate = context.coordinator
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
        var completion: (String?) -> Void
        var presentedID: UUID?
        var picker: NSSharingServicePicker?
        init(completion: @escaping (String?) -> Void) { self.completion = completion }
        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            if service == nil { finish(nil) }
        }
        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? { self }
        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish(nil) }
        func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) { finish(error.localizedDescription) }
        func finish(_ message: String?) {
            picker = nil
            DispatchQueue.main.async { self.completion(message) }
        }
    }
}
#endif

private struct ExportPreview: View {
    var page: NotePage
    var assets: [NotebookAsset]
    var includePaper: Bool
    var width: CGFloat = 180
    var body: some View {
        var preview = page
        if !includePaper { preview.paper = .blank }
        return PaperCanvas(page: preview, pending: nil, selection: nil, erased: [], assets: assets)
            .frame(width: width, height: width * 4 / 3).border(.gray.opacity(0.3))
    }
}
