import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let notedNotebook = UTType(exportedAs: "app.noted.notebook", conformingTo: .json)
}

struct NotebookDocument: FileDocument, Equatable {
    static var readableContentTypes: [UTType] { [.notedNotebook] }
    let loadID = UUID()
    var notebook: Notebook

    init(notebook: Notebook = Notebook()) { self.notebook = notebook }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        notebook = try Notebook.decode(data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try notebook.encoded())
    }
}

@main
struct NotedApp: App {
    var body: some Scene {
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
