import SwiftUI

private enum EditorTool: String, CaseIterable {
    case pen = "Pen", highlighter = "Highlight", eraser = "Erase", select = "Move", text = "Text"
    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .select: "cursorarrow.motionlines"
        case .text: "textformat"
        }
    }
}

struct NotebookEditor: View {
    @Binding var document: NotebookDocument
    var fileURL: URL?
    @State private var viewport = NotebookViewport()
    @State private var canvasSize = CGSize(width: 768, height: 1024)
    @State private var previousWritingTool: EditorTool = .pen
    @AppStorage("automaticallyAddPages") private var automaticallyAddPages = true
    @State private var showTemplates = false
    @State private var templateForNewPage = false
    private var zoom: Double { viewport.zoom }
    @State private var panMode = false
    @State private var recoveryCopies: [NotebookDocument] = []
    @State private var exportCopies: [NotebookDocument] = []
    @State private var showExport = false
    @State private var recoveryMessage = ""
    @State private var showRecovery = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPage: UUID?
    @State private var tool: EditorTool = .pen
    @State private var ink = "ink"
    @State private var width = 2.5
    @State private var pencilOnly = true
    @State private var pending: InkStroke?
    @State private var selectedStroke: UUID?
    @State private var selectedText: UUID?
    @State private var startPoint: InkPoint?
    @State private var originalStroke: InkStroke?
    @State private var originalText: TextCard?
    @State private var gesturePage: UUID?
    @State private var gestureBefore: Notebook?
    @State private var undoStack: [Notebook] = []
    @State private var redoStack: [Notebook] = []
    @State private var showDelete = false
    @State private var showHelp = false
    @State private var textEdit: TextEditTarget?
    @State private var pendingTextEdit: TextEditTarget?
    @State private var recordedTextUndo = false
    @State private var scrollOverflow = 0.0
    @State private var titleDraft = ""
    @State private var showTitle = false
    @State private var erasedIDs: Set<UUID> = []

    private let accent = Color(red: 0.16, green: 0.36, blue: 0.29)
    private var pageIndex: Int { document.notebook.pages.firstIndex { $0.id == selectedPage } ?? 0 }
    private var page: NotePage { document.notebook.pages[pageIndex] }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "leaf.fill").foregroundStyle(accent)
                    Text("Noted").font(.system(size: 28, weight: .semibold, design: .serif))
                    Spacer()
                }.padding(.horizontal, 20).padding(.top, 22)
                Text("ROOM TO THINK.").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 6)
                HStack {
                    Text("PAGES").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                    Spacer()
                    Button(action: addPage) { Image(systemName: "plus") }.buttonStyle(.borderless)
                        .help("Add page").accessibilityLabel("Add page")
                }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 10)
                List(selection: Binding(get: { selectedPage }, set: { id in
                    clearSelection(); selectedPage = id
                    viewport.showPage(pageIndex, in: canvasSize); scrollOverflow = 0
                })) {
                    ForEach(Array(document.notebook.pages.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            PaperCanvas(page: item, pending: nil, selection: nil, erased: [])
                                .frame(width: 42, height: 56).clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.gray.opacity(0.2)))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Page \(index + 1)").font(.system(size: 13, weight: .medium))
                                Text(item.paper.rawValue + " paper").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(.vertical, 6).tag(item.id)
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Your notebook. Your file.", systemImage: "doc").font(.system(size: 11, weight: .medium))
                    Text("Free to write. Free to keep.").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(20)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                tools.padding(.horizontal, 18).padding(.vertical, 12)
                Divider()
                GeometryReader { proxy in
                    notebookCanvas(size: proxy.size)
                        .onAppear { canvasSize = proxy.size }
                        .onChange(of: proxy.size) { _, size in
                            finish(false); canvasSize = size; viewport.clamp(in: size)
                        }
                }
                if selectedText != nil { textSelectionControls }
                HStack {
                    Text("PAGE \(pageIndex + 1) OF \(document.notebook.pages.count)")
                    Spacer()
                    Text(panMode ? "Drag to move the page" : tool == .select ? "Drag ink or text to move it" : tool == .text ? "Tap text to edit, or tap blank paper to type" : "\(tool.rawValue) · \(page.paper.rawValue) paper")
                    Spacer()
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
                        .buttonStyle(.plain).accessibilityLabel("Notebook help")
                }.font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 11)
            }
            .navigationTitle(document.notebook.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Rename notebook") { titleDraft = document.notebook.title; showTitle = true }
                        Button("Duplicate page", action: duplicatePage)
                        Button("Move page earlier") { reorder(-1) }.disabled(pageIndex == 0)
                        Button("Move page later") { reorder(1) }.disabled(pageIndex == document.notebook.pages.count - 1)
                        Button("Delete page", role: .destructive) { showDelete = true }.disabled(document.notebook.pages.count == 1)
                        Divider()
                        Button("Export notebook copy") { exportCopies = [NotebookDocument(notebook: document.notebook)]; showExport = true }
                        Button("Recover file versions", action: recoverVersions)
                        Button("Saving & syncing") { showHelp = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .tint(accent)
        .preferredColorScheme(.light)
        .onAppear {
            selectedPage = document.notebook.pages.first?.id
            viewport.pageCount = document.notebook.pages.count
        }
        .onChange(of: document) { old, new in
            if old.loadID != new.loadID {
                let previous = old.notebook
                recoveryCopies.append(NotebookDocument(notebook: previous))
                do { try saveRecovery(previous) }
                catch { recoveryMessage = "Recovery could not be saved to disk: \(error.localizedDescription). Export the retained copy before closing."; showRecovery = true }
                gestureBefore = nil; pendingTextEdit = nil; textEdit = nil; undoStack = []; redoStack = []; clearSelection()
                if !new.notebook.pages.contains(where: { $0.id == selectedPage }) { selectedPage = new.notebook.pages.first?.id }
                if recoveryMessage.isEmpty { recoveryMessage = "The file was reloaded. A previous notebook copy is available under Recover file versions. Undo history has been reset." }
                showRecovery = true
            }
        }
        .onChange(of: document.notebook.pages.count) { _, count in
            viewport.pageCount = count; viewport.clamp(in: canvasSize)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { finish(false) }
        }
        .fileExporter(isPresented: $showExport, documents: exportCopies, contentType: .notedNotebook) { result in
            if case .failure(let error) = result { recoveryMessage = error.localizedDescription; showRecovery = true }
        }
        .alert("File recovery", isPresented: $showRecovery) { Button("OK", role: .cancel) {} } message: { Text(recoveryMessage) }

        .onChange(of: tool) { _, _ in clearSelection() }
        .alert("Delete this page?", isPresented: $showDelete) {
            Button("Delete", role: .destructive) {
                remember(); clearSelection(); document.notebook.pages.remove(at: pageIndex)
                selectedPage = document.notebook.pages.first?.id
                viewport.pageCount = document.notebook.pages.count; viewport.showPage(pageIndex, in: canvasSize)
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("You can restore it with Undo while this notebook is open.") }
        .alert("Notebook title", isPresented: $showTitle) {
            TextField("Title", text: $titleDraft)
            Button("Save") {
                let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { remember(); document.notebook.title = title }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This changes the title inside the notebook. Rename its file separately in Files or Finder.") }
        .sheet(isPresented: $showHelp) { helpView }
        .sheet(isPresented: $showTemplates) { templatePicker }
    }

    private func notebookCanvas(size: CGSize) -> some View {
        let scale = viewport.scale(in: size)
        return ZStack(alignment: .topLeading) {
            Color(red: 0.92, green: 0.93, blue: 0.91)
            ForEach(Array(document.notebook.pages.enumerated()), id: \.element.id) { index, item in
                let origin = viewport.pageOrigin(at: index, in: size)
                if origin.y < size.height && origin.y + 1024 * scale > 0 {
                    ZStack(alignment: .topLeading) {
                        PaperCanvas(page: item, pending: gesturePage == item.id ? pending : nil,
                                    selection: selectedStroke, erased: gesturePage == item.id ? erasedIDs : [],
                                    editingText: textEdit?.pageID == item.id ? textEdit?.id : nil)
                        if let card = item.texts.first(where: { $0.id == selectedText }) {
                            RoundedRectangle(cornerRadius: 4).stroke(accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .frame(width: 310 * scale, height: 100 * scale)
                                .position(x: (card.x + 150) * scale, y: (card.y + 45) * scale)
                        }
                    }
                    .frame(width: 768 * scale, height: 1024 * scale)
                    .clipped().shadow(color: .black.opacity(0.09), radius: 12, y: 5)
                    .offset(x: origin.x, y: origin.y).allowsHitTesting(false)
                }
            }
            PointerSurface(pencilOnly: pencilOnly && (tool == .pen || tool == .highlighter || tool == .eraser), panMode: panMode,
                began: { point in
                    guard let index = viewport.pageIndex(at: point, in: size), document.notebook.pages.indices.contains(index) else { return }
                    clearSelection(); selectedPage = document.notebook.pages[index].id
                    begin(viewport.pagePoint(point, at: index, in: size))
                },
                moved: {
                    guard let index = document.notebook.pages.firstIndex(where: { $0.id == gesturePage }) else { return }
                    let p = viewport.pagePoint($0, at: index, in: size)
                    move(InkPoint(x: min(768, max(0, p.x)), y: min(1024, max(0, p.y)), pressure: p.pressure))
                }, ended: finish,
                panned: { scrollPages($0, size: size) },
                magnified: { viewport.magnify($0, at: $1, in: size); scrollOverflow = 0 },
                pencilTapped: {
                    clearSelection(); panMode = false
                    if tool == .eraser { tool = previousWritingTool }
                    else { previousWritingTool = tool; tool = .eraser }
                })
            if let target = textEdit,
               let index = document.notebook.pages.firstIndex(where: { $0.id == target.pageID }) {
                let origin = viewport.pageOrigin(at: index, in: size)
                InlineTextEditor(initialText: target.text) { value in updateText(value, target: target) }
                    .id(target.id)
                    .frame(width: 300, height: 90)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: origin.x + target.x * scale, y: origin.y + target.y * scale)
            }
        }.frame(width: size.width, height: size.height).clipped()
    }
    private func scrollPages(_ delta: CGSize, size: CGSize) {
        if textEdit != nil { clearSelection() }
        let overflow = viewport.pan(delta, in: size)
        if delta.height < 0 && overflow > 0 { scrollOverflow += overflow }
        else if delta.height != 0 { scrollOverflow = 0 }
        if automaticallyAddPages && scrollOverflow >= 72, let last = document.notebook.pages.last {
            remember()
            document.notebook.appendPageAfterScroll(after: last.id)
            viewport.pageCount = document.notebook.pages.count
            viewport.pan(CGSize(width: 0, height: -scrollOverflow), in: size)
            scrollOverflow = 0
        }
        let center = InkPoint(x: size.width / 2, y: size.height / 2)
        if let index = viewport.pageIndex(at: center, in: size), document.notebook.pages.indices.contains(index) {
            selectedPage = document.notebook.pages[index].id
        }
    }
    private func fitCurrentPage() {
        finish(false); viewport = NotebookViewport(pageCount: document.notebook.pages.count)
        viewport.showPage(pageIndex, in: canvasSize); scrollOverflow = 0
    }
    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { changeZoom(1 / 1.25) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 32, height: 42) }
                .disabled(zoom <= 1).accessibilityLabel("Zoom out")
            Button("\(Int((zoom * 100).rounded()))%") { fitCurrentPage() }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(minWidth: 42, minHeight: 42).help("Fit page")
            Button { changeZoom(1.25) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 32, height: 42) }
                .disabled(zoom >= 4).accessibilityLabel("Zoom in")
        }.buttonStyle(.plain)
    }
    private func changeZoom(_ factor: Double) {
        finish(false)
        viewport.magnify(factor, at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2), in: canvasSize)
    }
    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(templateForNewPage ? "A little more space." : "Choose your paper.")
                        .font(.system(size: 26, weight: .medium, design: .serif))
                    Text(templateForNewPage ? "Add a page after this one." : "Your writing stays exactly where it is.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { showTemplates = false }
            }
            HStack(spacing: 16) {
                ForEach(Paper.allCases, id: \.self) { paper in
                    Button {
                        remember()
                        if templateForNewPage {
                            clearSelection()
                            let new = NotePage(paper: paper)
                            document.notebook.pages.insert(new, at: pageIndex + 1); selectedPage = new.id
                            viewport.pageCount = document.notebook.pages.count; viewport.showPage(pageIndex, in: canvasSize)
                        } else { document.notebook.pages[pageIndex].paper = paper }
                        showTemplates = false
                    } label: {
                        VStack(spacing: 12) {
                            PaperCanvas(page: NotePage(paper: paper), pending: nil, selection: nil, erased: [])
                                .frame(width: 115, height: 154)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.25)))
                            Text(paper.rawValue).font(.headline)
                        }.padding(8)
                    }.buttonStyle(.plain).accessibilityLabel("\(paper.rawValue) template")
                }
            }
            Toggle("Add pages as you scroll", isOn: $automaticallyAddPages)
            Text("Scroll beyond the bottom of the notebook to add another page with the same paper. Writing alone does not add pages.")
                .font(.callout).foregroundStyle(.secondary)
        }.padding(28).frame(idealWidth: 510).tint(accent)
    }

    private var tools: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { toolPicker; inkControls; Spacer(minLength: 4); zoomControls; pageControls }
            VStack(spacing: 12) {
                HStack { toolPicker; Spacer(); historyControls }
                HStack { inkControls; Spacer(); zoomControls; paperPicker }
            }
        }
    }
    private var toolPicker: some View {
        HStack(spacing: 4) {
            ForEach(EditorTool.allCases, id: \.self) { item in
                Button { clearSelection(); panMode = false; tool = item } label: {
                    Image(systemName: item.symbol).font(.system(size: 16))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(tool == item && !panMode ? .white : accent)
                        .background(tool == item && !panMode ? accent : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).help(item.rawValue).accessibilityLabel(item.rawValue)
                    .accessibilityAddTraits(tool == item && !panMode ? [.isSelected] : [])
            }
            Button { clearSelection(); panMode.toggle() } label: {
                Image(systemName: "hand.draw").font(.system(size: 17))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(panMode ? .white : accent)
                    .background(panMode ? accent : .clear, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).help("Hand · drag the page").accessibilityLabel("Hand")
                .accessibilityAddTraits(panMode ? [.isSelected] : [])
        }
    }
    private var inkControls: some View {
        HStack(spacing: 10) {
            ForEach(["ink", "green", "blue", "red", "gold"], id: \.self) { color in
                Button { ink = color } label: {
                    Circle().fill(inkColor(color)).frame(width: 17, height: 17)
                        .padding(3).overlay(Circle().stroke(ink == color ? accent : .clear, lineWidth: 1.5))
                }.buttonStyle(.plain).accessibilityLabel("\(color) ink")
            }
            Menu {
                Button("Fine") { width = 1.5 }
                Button("Medium") { width = 2.5 }
                Button("Bold") { width = 5 }
            } label: { Image(systemName: "lineweight") }.menuStyle(.borderlessButton).fixedSize().help("Stroke width")
        }
    }
    private var pageControls: some View {
        HStack(spacing: 12) { historyControls; paperPicker }
    }
    private var historyControls: some View {
        HStack(spacing: 12) {
            Button(action: undo) { Image(systemName: "arrow.uturn.backward") }.disabled(undoStack.isEmpty).help("Undo").accessibilityLabel("Undo")
            Button(action: redo) { Image(systemName: "arrow.uturn.forward") }.disabled(redoStack.isEmpty).help("Redo").accessibilityLabel("Redo")
        }.buttonStyle(.plain)
    }
    private var paperPicker: some View {
        Menu {
            Button("Page templates…") { templateForNewPage = false; showTemplates = true }
            Toggle("Add pages as you scroll", isOn: $automaticallyAddPages)
            #if os(iOS)
            Divider()
            Toggle("Apple Pencil only", isOn: $pencilOnly)
            #endif
        } label: { Image(systemName: "square.grid.3x3") }.menuStyle(.borderlessButton).fixedSize().help("Paper & input").accessibilityLabel("Paper and input")
    }
    private var textSelectionControls: some View {
        HStack(spacing: 16) {
            Label("Text selected", systemImage: "textformat").foregroundStyle(.secondary)
            Spacer()
            Button("Edit text") {
                guard let card = page.texts.first(where: { $0.id == selectedText }) else { return }
                recordedTextUndo = false
                textEdit = TextEditTarget(pageID: page.id, card: card)
            }
            Button(role: .destructive) {
                remember(); document.notebook.pages[pageIndex].texts.removeAll { $0.id == selectedText }; clearSelection()
            } label: { Image(systemName: "trash") }.accessibilityLabel("Delete text")
            Button("Done") { clearSelection() }
        }.padding(12)
    }
    private func updateText(_ value: String, target: TextEditTarget) {
        guard let index = document.notebook.pages.firstIndex(where: { $0.id == target.pageID }) else { return }
        if value.isEmpty && !document.notebook.pages[index].texts.contains(where: { $0.id == target.id }) { return }
        guard document.notebook.pages[index].texts.first(where: { $0.id == target.id })?.text != value else { return }
        if !recordedTextUndo { remember(); recordedTextUndo = true }
        document.notebook.pages[index].updateText(id: target.id, text: value, x: target.x, y: target.y)
        selectedText = target.id
    }
    private var helpView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Make yourself a little space.").font(.system(size: 28, weight: .medium, design: .serif))
            Text("Noted · First prototype").font(.subheadline).foregroundStyle(.secondary)
            Label("Write on iPad. Keep editing on Mac.", systemImage: "pencil.and.outline")
            Text("Pen and Highlight draw; Erase removes whole strokes. Move lets you select and drag ink or text. Tap an existing block with Text to edit it, or tap blank paper to type directly on the page. Changes save as you type. Use two fingers to pan or pinch to zoom at any time. The hand tool enables one-finger dragging. On Mac, scroll or pinch the trackpad to navigate. Double-tap a supported Apple Pencil to switch between eraser and your writing tool (unless disabled in system settings). Choose Text, then tap the paper to add a text block. On iPad, Apple Pencil is enabled by default; switch off Apple Pencil only in the paper menu to use a finger.")
            Label("One editable .noted file", systemImage: "doc.badge.arrow.up")
            Text("Use the system document controls to save, open, or move your notebook. Save in iCloud Drive to share the same file between your iPad and Mac. Both devices need the app and the same Apple Account. Wait for iCloud to finish before switching devices; use Recover file versions to export system-reported conflicts and retained reload copies. Conflicts are left unresolved; automatic conflict merging is not implemented. A sequential handoff has been reported working; concurrent editing and recovery still need testing.")
            Text("No account with Noted, ads, subscriptions, or hosted backend. iCloud storage limits still apply. PDF import/export and handwriting recognition are not included yet.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Back to my notebook") { showHelp = false }.buttonStyle(.borderedProminent)
        }.padding(32).frame(idealWidth: 510)
    }

    private var recoveryDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Noted/Recovery", isDirectory: true)
    }
    private func saveRecovery(_ book: Notebook) throws {
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        try book.encoded().write(to: recoveryDirectory.appendingPathComponent(UUID().uuidString + ".noted"), options: .atomic)
    }
    private func recoverVersions() {
        exportCopies = recoveryCopies
        do {
            if FileManager.default.fileExists(atPath: recoveryDirectory.path) {
                for url in try FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: nil) where url.pathExtension == "noted" {
                    let book = try Notebook.decode(Data(contentsOf: url))
                    if !exportCopies.contains(where: { $0.notebook == book }) { exportCopies.append(NotebookDocument(notebook: book)) }
                }
            }
        } catch {
            recoveryMessage = "A saved recovery copy could not be read: \(error.localizedDescription)"; showRecovery = true; return
        }
        if let fileURL {
            let scoped = fileURL.startAccessingSecurityScopedResource()
            defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
            for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) ?? [] {
                do {
                    let book = try Notebook.decode(Data(contentsOf: version.url))
                    exportCopies.append(NotebookDocument(notebook: book))
                } catch {
                    recoveryMessage = "A conflict version could not be read: \(error.localizedDescription). It has been left unresolved."
                    showRecovery = true
                    return
                }
            }
        }
        if exportCopies.isEmpty {
            recoveryMessage = "No retained reload copies or system-reported conflict versions are available. This does not confirm that iCloud has finished syncing."
            showRecovery = true
        } else {
            // Export includes the current version too. Never mark conflicts resolved or replace the source.
            exportCopies.insert(NotebookDocument(notebook: document.notebook), at: 0)
            showExport = true
        }
    }

    private func begin(_ p: InkPoint) {
        guard (0...768).contains(p.x), (0...1024).contains(p.y) else { return }
        clearSelection(); gestureBefore = document.notebook; gesturePage = page.id; startPoint = p
        switch tool {
        case .pen, .highlighter:
            pending = InkStroke(points: [p], color: ink, width: tool == .highlighter ? width * 7 : width, isHighlighter: tool == .highlighter)
        case .eraser: erase(p)
        case .select:
            selectedText = page.texts.last(where: { p.x >= $0.x && p.x <= $0.x+300 && p.y >= $0.y && p.y <= $0.y+90 })?.id
            if let selectedText, let card = page.texts.first(where: { $0.id == selectedText }) {
                originalText = card; selectedStroke = nil
            } else {
                selectedStroke = page.strokes.last(where: { $0.distance(to: p) <= max(14, $0.width) })?.id
                originalStroke = page.strokes.first { $0.id == selectedStroke }
            }
        case .text:
            let card = page.text(at: p) ?? TextCard(x: min(p.x, 448), y: min(p.y, 914))
            pendingTextEdit = TextEditTarget(pageID: page.id, card: card)
        }
    }
    private func move(_ p: InkPoint) {
        guard let startPoint else { return }
        switch tool {
        case .pen, .highlighter: pending?.points.append(p)
        case .eraser: erase(p)
        case .select:
            if let originalStroke, let i = page.strokes.firstIndex(where: { $0.id == originalStroke.id }) {
                let xs = originalStroke.points.map(\.x), ys = originalStroke.points.map(\.y)
                let dx = max(-(xs.min() ?? 0), min(768-(xs.max() ?? 768), p.x-startPoint.x))
                let dy = max(-(ys.min() ?? 0), min(1024-(ys.max() ?? 1024), p.y-startPoint.y))
                document.notebook.pages[pageIndex].strokes[i] = originalStroke.translated(x: dx, y: dy)
            }
            if let originalText, let i = page.texts.firstIndex(where: { $0.id == originalText.id }) {
                document.notebook.pages[pageIndex].texts[i].x = max(0, min(448, originalText.x+p.x-startPoint.x))
                document.notebook.pages[pageIndex].texts[i].y = max(0, min(914, originalText.y+p.y-startPoint.y))
            }
        case .text: break
        }
    }
    private func erase(_ p: InkPoint) {
        for stroke in page.strokes where stroke.distance(to: p) < max(12, stroke.width/2) { erasedIDs.insert(stroke.id) }
    }
    private func finish(_ cancelled: Bool) {
        guard gestureBefore != nil else { return }
        if cancelled {
            if let gestureBefore { document.notebook = gestureBefore }; selectedStroke = nil; selectedText = nil
        } else {
            if let index = document.notebook.pages.firstIndex(where: { $0.id == gesturePage }) {
                if let pending { document.notebook.pages[index].strokes.append(pending) }
                document.notebook.pages[index].strokes.removeAll { erasedIDs.contains($0.id) }
            }
            if let gestureBefore, gestureBefore != document.notebook {
                pushUndo(gestureBefore)
            }
        }
        let edit = cancelled ? nil : pendingTextEdit
        pendingTextEdit = nil
        pending = nil; startPoint = nil; originalStroke = nil; originalText = nil; gestureBefore = nil; erasedIDs = []
        if let edit { recordedTextUndo = false; selectedText = edit.id; textEdit = edit }
    }
    private func clearSelection() {
        finish(false)
        textEdit = nil
        selectedStroke = nil; selectedText = nil; pending = nil; startPoint = nil
        originalStroke = nil; originalText = nil; erasedIDs = []; gestureBefore = nil
    }
    private func pushUndo(_ book: Notebook) {
        undoStack.append(book)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack = []
    }
    private func remember() { finish(false); pushUndo(document.notebook) }
    private func undo() {
        finish(false)
        guard let book = undoStack.popLast() else { return }
        redoStack.append(document.notebook); document.notebook = book; clearSelection()
        if !book.pages.contains(where: { $0.id == selectedPage }) { selectedPage = book.pages.first?.id }
    }
    private func redo() {
        finish(false)
        guard let book = redoStack.popLast() else { return }
        undoStack.append(document.notebook); document.notebook = book; clearSelection()
        if !book.pages.contains(where: { $0.id == selectedPage }) { selectedPage = book.pages.first?.id }
    }
    private func addPage() {
        templateForNewPage = true; showTemplates = true
    }
    private func duplicatePage() {
        remember(); clearSelection(); var copy = page; copy.id = UUID()
        document.notebook.pages.insert(copy, at: pageIndex+1); selectedPage = copy.id
        viewport.pageCount = document.notebook.pages.count; viewport.showPage(pageIndex, in: canvasSize)
    }
    private func reorder(_ delta: Int) {
        let destination = pageIndex + delta
        guard document.notebook.pages.indices.contains(destination) else { return }
        remember(); clearSelection(); document.notebook.pages.swapAt(pageIndex, destination)
        viewport.showPage(pageIndex, in: canvasSize)
    }
}

func inkColor(_ name: String) -> Color {
    switch name {
    case "green": Color(red: 0.16, green: 0.40, blue: 0.31)
    case "blue": Color(red: 0.22, green: 0.38, blue: 0.65)
    case "red": Color(red: 0.72, green: 0.29, blue: 0.25)
    case "gold": Color(red: 0.88, green: 0.68, blue: 0.20)
    default: Color(red: 0.18, green: 0.22, blue: 0.23)
    }
}

struct PaperCanvas: View {
    var page: NotePage
    var pending: InkStroke?
    var selection: UUID?
    var erased: Set<UUID>
    var editingText: UUID? = nil
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width/768, y: size.height/1024)
            context.fill(Path(CGRect(x: 0, y: 0, width: 768, height: 1024)), with: .color(Color(red: 1, green: 0.995, blue: 0.98)))
            if page.paper != .blank {
                var lines = Path()
                let step = page.paper == .grid ? 24 : 32
                for y in stride(from: 64, through: 992, by: step) {
                    lines.move(to: CGPoint(x: 40, y: y)); lines.addLine(to: CGPoint(x: 728, y: y))
                }
                if page.paper == .grid {
                    for x in stride(from: 40, through: 728, by: 24) {
                        lines.move(to: CGPoint(x: x, y: 64)); lines.addLine(to: CGPoint(x: x, y: 992))
                    }
                }
                context.stroke(lines, with: .color(.gray.opacity(0.17)), lineWidth: 0.6)
            }
            for stroke in page.strokes + (pending.map { [$0] } ?? []) where !erased.contains(stroke.id) {
                guard let first = stroke.points.first else { continue }
                var inkContext = context
                // Opacity on a layer keeps overlapping segments of one highlight even.
                inkContext.opacity = stroke.isHighlighter ? 0.28 : 1
                inkContext.drawLayer { layer in
                    if stroke.points.count == 1 {
                        layer.fill(Path(ellipseIn: CGRect(x: first.x-stroke.width/2, y: first.y-stroke.width/2, width: stroke.width, height: stroke.width)), with: .color(inkColor(stroke.color)))
                    }
                    for (a, b) in zip(stroke.points, stroke.points.dropFirst()) {
                        var path = Path(); path.move(to: CGPoint(x: a.x, y: a.y)); path.addLine(to: CGPoint(x: b.x, y: b.y))
                        let pressure = stroke.isHighlighter ? 1 : 0.45 + 0.55 * (a.pressure+b.pressure)/2
                        layer.stroke(path, with: .color(inkColor(stroke.color)), style: StrokeStyle(lineWidth: stroke.width*pressure, lineCap: .round, lineJoin: .round))
                    }
                }
                if stroke.id == selection {
                    let xs = stroke.points.map(\.x), ys = stroke.points.map(\.y)
                    let rect = CGRect(x: (xs.min() ?? 0)-8, y: (ys.min() ?? 0)-8, width: (xs.max() ?? 0)-(xs.min() ?? 0)+16, height: (ys.max() ?? 0)-(ys.min() ?? 0)+16)
                    context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(inkColor("green")), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
            }
            for card in page.texts where card.id != editingText {
                context.draw(Text(card.text).font(.system(size: 20)).foregroundColor(inkColor("ink")), in: CGRect(x: card.x, y: card.y, width: 300, height: 90))
            }
        }.accessibilityLabel("Notebook page, \(page.strokes.count) strokes and \(page.texts.count) text blocks")
    }
}


private struct TextEditTarget: Identifiable {
    let id: UUID
    let pageID: UUID
    let text: String
    let x: Double
    let y: Double
    init(pageID: UUID, card: TextCard) {
        self.pageID = pageID; id = card.id; text = card.text; x = card.x; y = card.y
    }
}

private struct InlineTextEditor: View {
    @FocusState private var focused: Bool
    @State private var text: String
    var onEdit: (String) -> Void
    init(initialText: String, onEdit: @escaping (String) -> Void) {
        _text = State(initialValue: initialText); self.onEdit = onEdit
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 20)).foregroundStyle(inkColor("ink"))
                .scrollContentBackground(.hidden)
                .focused($focused).accessibilityLabel("Text on page")
            if text.isEmpty {
                Text("Type here…").font(.system(size: 20)).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 8).allowsHitTesting(false)
            }
        }
        .background(Color(red: 1, green: 0.995, blue: 0.98).opacity(0.95))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(inkColor("green"), lineWidth: 1))
        .onChange(of: text) { _, value in onEdit(value) }
        .task { focused = true }
    }
}
