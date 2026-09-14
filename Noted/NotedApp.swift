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
    #if os(macOS)
    @NSApplicationDelegateAdaptor(NotedApplicationDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        Window("Noted · Notebooks", id: "notebooks") {
            MacNotebookHome().frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 940, height: 620)
        .windowStyle(.hiddenTitleBar)
        .commands { NotebookHomeCommands() }
        #else
        if #available(iOS 18.0, *) {
            DocumentGroupLaunchScene(Text("Noted").font(.system(size: 64, weight: .medium, design: .serif)).foregroundStyle(Color(red: 0.16, green: 0.36, blue: 0.29))) {
                NewDocumentButton("New notebook", for: NotebookDocument.self)
                    .tint(Color(red: 0.16, green: 0.36, blue: 0.29))
            } background: {
                NotebookWelcomeBackground()
            }
        }
        #endif
        notebookDocuments
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

struct NotebookWelcomeBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.96, green: 0.95, blue: 0.91)
                Canvas { context, size in
                    var lines = Path()
                    for y in stride(from: 0.0, through: size.height, by: 32) {
                        lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(lines, with: .color(.gray.opacity(0.09)), lineWidth: 0.7)
                    var curve = Path()
                    curve.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.38))
                    curve.addCurve(to: CGPoint(x: size.width * 0.92, y: size.height * 0.37),
                        control1: CGPoint(x: size.width * 0.28, y: size.height * 0.27),
                        control2: CGPoint(x: size.width * 0.65, y: size.height * 0.50))
                    context.stroke(curve, with: .color(.green.opacity(0.10)), style: StrokeStyle(lineWidth: 28, lineCap: .round))
                }
                VStack {
                    Label("A little space for your ideas.", systemImage: "leaf")
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(Color(red: 0.16, green: 0.36, blue: 0.29))
                        .padding(.top, proxy.size.height * 0.10)
                    Spacer()
                }
            }
        }.ignoresSafeArea()
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

struct MacNotebookHome: View {
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @Environment(\.scenePhase) private var scenePhase
    @State private var recentURLs: [URL] = []
    @State private var paper: Paper = .ruled
    @State private var openError: String?
    private let accent = Color(red: 0.16, green: 0.36, blue: 0.29)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "leaf").font(.system(size: 36, weight: .light))
                Text("Noted").font(.system(size: 54, weight: .medium, design: .serif))
                Text("A little space\nfor your ideas.")
                    .font(.system(size: 23, design: .serif)).lineSpacing(5)
                Spacer()
                Text("Write on iPad.\nMake it yours on Mac.").font(.callout).lineSpacing(4)
                Text("Your notebooks. Your files.").font(.caption).foregroundStyle(.secondary)
            }.foregroundStyle(accent).padding(36).frame(width: 285)
                .frame(maxHeight: .infinity)
                .background(Color(red: 0.93, green: 0.94, blue: 0.88))
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Your notebooks").font(.system(size: 25, weight: .semibold, design: .serif))
                    Spacer()
                    Button { refreshRecents() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help("Refresh recent notebooks")
                }
                HStack(spacing: 12) {
                    Button {
                        let selectedPaper = paper
                        newDocument(NotebookDocument(notebook: Notebook(pages: [NotePage(paper: selectedPaper)])))
                    } label: { Label("New notebook", systemImage: "plus").padding(.vertical, 5) }
                        .buttonStyle(.borderedProminent)
                    Button { NSDocumentController.shared.openDocument(nil) } label: {
                        Label("Open…", systemImage: "folder").padding(.vertical, 5)
                    }.buttonStyle(.bordered)
                }
                Picker("New notebook paper", selection: $paper) {
                    ForEach(Paper.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Divider()
                Text("RECENT").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                if recentURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "books.vertical").font(.system(size: 30, weight: .light)).foregroundStyle(accent)
                        Text("Your next idea starts here.").font(.headline)
                        Text("Create a notebook, or open a .noted file from your Mac or iCloud Drive.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 18)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(recentURLs, id: \.self) { url in
                                Button { Task {
                                    do { try await openDocument(at: url) }
                                    catch { openError = error.localizedDescription }
                                } } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "book.closed").font(.system(size: 23)).foregroundStyle(accent)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(url.deletingPathExtension().lastPathComponent).font(.headline)
                                            Text(url.deletingLastPathComponent().lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                                    }.padding(14).contentShape(Rectangle())
                                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(red: 0.98, green: 0.98, blue: 0.96)).tint(accent)
        .preferredColorScheme(.light)
        .onAppear(perform: refreshRecents)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshRecents() } }
        .alert("Couldn’t open notebook", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) { openError = nil }
        } message: { Text(openError ?? "") }
    }
    private func refreshRecents() {
        recentURLs = NSDocumentController.shared.recentDocumentURLs.filter { $0.pathExtension.lowercased() == "noted" }
    }
}
#endif
