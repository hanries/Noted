import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let notedNotebook = UTType(exportedAs: "app.noted.notebook", conformingTo: .json)
}

struct NotebookDocument: FileDocument, Equatable {
    static var readableContentTypes: [UTType] { [.notedNotebook] }
    let loadID = UUID()
    var notebook: Notebook

    init(notebook: Notebook = Notebook.newNotebook()) { self.notebook = notebook }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        notebook = try Notebook.decode(data)
        try NotebookTransfer.validate(notebook)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try notebook.encoded())
    }
}

@main
struct NotedApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(NotedApplicationDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        Window("Noted · Notebooks", id: "notebooks") {
            NotebookLibrary().frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 940, height: 620)
        .windowStyle(.hiddenTitleBar)
        .commands { NotebookHomeCommands() }
        notebookDocuments
        #else
        WindowGroup { NotebookLibrary() }
        #endif
    }

    private var notebookDocuments: some Scene {
        DocumentGroup(newDocument: NotebookDocument()) { file in
            #if os(macOS)
            NotebookEditor(document: file.$document, fileURL: file.fileURL)
                .frame(minWidth: 800, minHeight: 620)
            #else
            NotebookEditor(document: file.$document, fileURL: file.fileURL)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 820)
        #endif
    }
}

#if os(macOS)
import AppKit

final class NotedApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}

struct NotebookHomeCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Notebooks") { openWindow(id: "notebooks") }
                .keyboardShortcut("1", modifiers: [.command, .shift])
        }
    }
}

#endif
