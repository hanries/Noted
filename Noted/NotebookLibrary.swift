import SwiftUI
import UniformTypeIdentifiers

struct LibraryEntry: Identifiable {
    var id: URL { url }
    var url: URL
    var title: String
    var modified: Date
    var thumbnail: CGImage?
}

enum NotebookStorage {
    static var library: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Noted", isDirectory: true)
    }
    static var recovery: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Noted/Recovery", isDirectory: true)
    }
    static func backup(_ notebook: Notebook) throws {
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        try notebook.encoded().write(to: recovery.appendingPathComponent(UUID().uuidString + ".noted"), options: .atomic)
    }
    static func create(_ notebook: Notebook) throws -> URL {
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let name = notebook.title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = name.isEmpty ? "Untitled notebook" : String(name.prefix(100))
        var url = library.appendingPathComponent(base + ".noted"), number = 2
        while FileManager.default.fileExists(atPath: url.path) { url = library.appendingPathComponent("\(base) \(number).noted"); number += 1 }
        let temporary = library.appendingPathComponent("." + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try notebook.encoded().write(to: temporary, options: .atomic)
        try FileManager.default.moveItem(at: temporary, to: url)
        return url
    }
    static func location(_ url: URL?) -> String {
        guard let url else { return "Not saved yet" }
        if url.standardizedFileURL.path.hasPrefix(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].standardizedFileURL.path + "/") {
            #if os(iOS)
            return "On My iPad"
            #else
            return "On My Mac"
            #endif
        }
        return "Files · " + url.deletingLastPathComponent().lastPathComponent
    }
    static func entries() throws -> [LibraryEntry] {
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let urls = try [library, root].flatMap { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) }
        return urls.filter { $0.pathExtension.lowercased() == "noted" }.map { url in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let book = try? Notebook.decode(Data(contentsOf: url))
                let image = book.flatMap { book in book.pages.first.flatMap { NotebookRenderer.image(page: $0, assets: book.assets ?? [], paper: true, scale: 0.2) } }
                return LibraryEntry(url: url, title: book?.title ?? url.deletingPathExtension().lastPathComponent, modified: modified, thumbnail: image)
            }.sorted { $0.modified > $1.modified }
    }
}

struct NotebookLibrary: View {
    #if os(macOS)
    @Environment(\.openDocument) private var openDocument
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [LibraryEntry] = []
    @State private var showImport = false
    @State private var showOpen = false
    @State private var showNew = false
    @State private var title = ""
    @State private var paper: Paper = .ruled
    @State private var error: String?
    @State private var search = ""
    @State private var opened: OpenNotebookRequest?
    @State private var refreshing = false
    @State private var movedURL: URL?
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    Button { title = ""; showNew = true } label: { Label("New notebook", systemImage: "plus") }.buttonStyle(.borderedProminent)
                    Button { showImport = true } label: { Label("Import", systemImage: "square.and.arrow.down") }.buttonStyle(.bordered)
                    Button { showOpen = true } label: { Label("Open from Files", systemImage: "folder") }.buttonStyle(.bordered)
                }.padding(.top)
                Text("Your notebooks, saved on this device. Shared storage is optional.").foregroundStyle(.secondary)
                if refreshing { ProgressView() }
                List {
                    ForEach(entries.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { entry in
                        Button { open(entry.url) } label: {
                            HStack(spacing: 16) {
                                if let image = entry.thumbnail { Image(decorative: image, scale: 1).resizable().frame(width: 48, height: 64).border(.gray.opacity(0.2)) }
                                else { Image(systemName: "book.closed").frame(width: 48, height: 64) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.title).font(.headline)
                                    Text(NotebookStorage.location(entry.url)).font(.caption).foregroundStyle(.secondary)
                                    Text(entry.modified, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }.padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.overlay {
                    if entries.isEmpty && !refreshing { ContentUnavailableView("A place for your ideas", systemImage: "book.closed", description: Text("Create a notebook or import your notes. No account needed.")) }
                }
            }
            .navigationTitle("Notebooks").searchable(text: $search, prompt: "Find a notebook")
            .toolbar { Button { refresh() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh notebooks") }
        }.tint(inkColor("green"))
            .task { refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
            .sheet(isPresented: $showNew) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("New notebook").font(.title2)
                    TextField("Notebook name", text: $title).textFieldStyle(.roundedBorder)
                    Picker("Paper", selection: $paper) { ForEach(Paper.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    Text("Saved on this device. You can move it to another location later.").font(.callout).foregroundStyle(.secondary)
                    HStack { Button("Cancel") { showNew = false }; Spacer(); Button("Create") {
                        do {
                            let book = Notebook(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled notebook" : title, pages: [NotePage(paper: paper)])
                            let url = try NotebookStorage.create(book); showNew = false; refresh()
                            DispatchQueue.main.async { open(url) }
                        } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent) }
                }.padding(28).frame(idealWidth: 460)
            }
            .sheet(isPresented: $showImport) {
                NotebookImportSheet { book in
                    _ = try NotebookStorage.create(book); refresh()
                }
            }
            .alert("Notebook storage", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            #if os(iOS)
            .sheet(isPresented: $showOpen) { OpenNotebookPicker { url in showOpen = false; if let url { DispatchQueue.main.async { open(url) } } } }
            .fullScreenCover(item: $opened, onDismiss: {
                refresh()
                if let movedURL { self.movedURL = nil; open(movedURL) }
            }) { request in IPadNotebookSession(url: request.url, onMoved: { movedURL = $0 }) }
            .onOpenURL { url in
                if opened == nil { open(url) } else { error = "Close the current notebook before opening another file." }
            }
            #else
            .fileImporter(isPresented: $showOpen, allowedContentTypes: [.notedNotebook]) { result in
                switch result { case .success(let url): open(url); case .failure(let error): self.error = error.localizedDescription }
            }
            #endif
    }
    private func open(_ url: URL) {
        #if os(iOS)
        opened = OpenNotebookRequest(url: url)
        #else
        Task {
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { try await openDocument(at: url) } catch { self.error = error.localizedDescription }
        }
        #endif
    }
    private func refresh() {
        guard !refreshing else { return }; refreshing = true
        Task {
            do { entries = try await Task.detached { try NotebookStorage.entries() }.value }
            catch { self.error = error.localizedDescription }
            refreshing = false
        }
    }
}

private struct OpenNotebookRequest: Identifiable { let id = UUID(); let url: URL }

#if os(iOS)
import UIKit

private struct OpenNotebookPicker: UIViewControllerRepresentable {
    var completion: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.notedNotebook], asCopy: false)
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void
        init(_ completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}

final class IPadNotebookDocument: UIDocument, ObservableObject {
    @Published var value = NotebookDocument()
    @Published var failure: String?
    private var loaded = false
    override func contents(forType typeName: String) throws -> Any {
        guard !documentState.contains(.inConflict) else { throw TransferError(message: "Conflicting file versions need recovery before saving over this file.") }
        return try value.notebook.encoded()
    }
    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data else { throw CocoaError(.fileReadCorruptFile) }
        let book = try Notebook.decode(data)
        try NotebookTransfer.validate(book)
        if loaded { try NotebookStorage.backup(value.notebook) }
        value = NotebookDocument(notebook: book); loaded = true
    }
    override func handleError(_ error: Error, userInteractionPermitted: Bool) {
        DispatchQueue.main.async { self.failure = "Saving needs attention: \(error.localizedDescription). Keep this notebook open or export a recovery copy." }
        super.handleError(error, userInteractionPermitted: userInteractionPermitted)
    }
}

private struct IPadNotebookSession: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let url: URL
    var onMoved: (URL) -> Void
    @StateObject private var file: IPadNotebookDocument
    @State private var ready = false
    @State private var busy = false
    @State private var scoped = false
    @State private var started = false
    @State private var moveFile = false
    @State private var error: String?
    init(url: URL, onMoved: @escaping (URL) -> Void) { self.url = url; self.onMoved = onMoved; _file = StateObject(wrappedValue: IPadNotebookDocument(fileURL: url)) }
    var body: some View {
        ZStack {
            if ready {
                NotebookEditor(document: Binding(get: { file.value }, set: { file.value = $0; file.updateChangeCount(.done) }), fileURL: file.fileURL,
                               onClose: close, onMove: prepareMove,
                               storageStatus: file.documentState.contains(.inConflict) ? "File conflict · recover versions" : "Changes save automatically. Your drive manages any cloud uploads.")
                    .disabled(busy)
            } else {
                VStack(spacing: 20) { if busy { ProgressView("Opening notebook…") }; Button("Back to notebooks") { dismiss() } }
            }
        }
        .task {
            // SwiftUI may restart this task when the loading view becomes the editor.
            // UIDocument must never receive overlapping open operations.
            guard !started else { return }
            started = true
            scoped = url.startAccessingSecurityScopedResource(); busy = true
            ready = await file.open(); busy = false
            if !ready { error = "Couldn’t open this notebook. Check that the file is downloaded and that your drive is available." }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active && ready && !busy { file.save(to: file.fileURL, for: .forOverwriting) } }
        .onDisappear { if scoped { url.stopAccessingSecurityScopedResource() } }
        .interactiveDismissDisabled()
        .alert("Notebook storage", isPresented: Binding(get: { error != nil || file.failure != nil }, set: { if !$0 { error = nil; file.failure = nil } })) {
            Button("OK") { error = nil; file.failure = nil }
        } message: { Text(error ?? file.failure ?? "") }
        .sheet(isPresented: $moveFile) {
            MoveNotebookPicker(url: file.fileURL) { destination in
                moveFile = false
                if let destination { onMoved(destination); ready = false; dismiss() }
                else { Task {
                    ready = await file.open(); busy = false
                    if !ready { error = "Couldn’t reopen the original file after cancelling the move. A recovery copy is retained." }
                } }
            }.interactiveDismissDisabled()
        }
    }

    private func close() {
        busy = true
        Task {
            let success = await file.close(); busy = false
            if success { dismiss() } else { error = "Couldn’t save and close. Export a copy before leaving this notebook." }
        }
    }
    private func prepareMove() {
        do { try NotebookStorage.backup(file.value.notebook) }
        catch { self.error = "A safety copy couldn’t be saved: \(error.localizedDescription)"; return }
        busy = true
        Task {
            if await file.close() { moveFile = true } else { busy = false; error = "Save failed. The notebook hasn’t been moved." }
        }
    }
}

private struct MoveNotebookPicker: UIViewControllerRepresentable {
    let url: URL
    var completion: (URL?) -> Void
    func makeCoordinator() -> OpenNotebookPicker.Coordinator { OpenNotebookPicker.Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: false)
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}

#endif
