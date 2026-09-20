import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

private enum EditorTool: String, CaseIterable {
    case pen = "Pen", pencil = "Pencil", eraser = "Erase", select = "Selection", text = "Text"
    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .pencil: "pencil"
        case .eraser: "eraser"
        case .select: "rectangle.dashed"
        case .text: "textformat"
        }
    }
}

struct NotebookEditor: View {
    @Binding var document: NotebookDocument
    var fileURL: URL?
    var onClose: (() -> Void)? = nil
    var onMove: (() -> Void)? = nil
    var storageStatus = "Changes save through the system document interface."
    @State private var showTransferExport = false
    @State private var showTransferImport = false
    @State private var showStorage = false
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
    @AppStorage("penInk") private var penInk = "ink"
    @AppStorage("pencilInk") private var pencilInk = "ink"
    @AppStorage("penWidth") private var penWidth = 2.5
    @AppStorage("pencilWidth") private var pencilWidth = 4.0
    @AppStorage("pencilOnly") private var pencilOnly = true
    @AppStorage("eraseWholeStroke") private var eraseWholeStroke = false
    @AppStorage("eraserRadius") private var eraserRadius = 12.0
    @AppStorage("rectangleSelection") private var rectangleSelection = false
    @State private var toolPopover: EditorTool?
    @State private var liveInk = LiveInk()
    @State private var gesturePreview: NotePage?
    @State private var resizingSelection = false
    @State private var backedUpForModernEdit = false
    @State private var lastErase: InkPoint?
    @State private var showImageFile = false
    @State private var showPhotoLibrary = false
    @State private var navigationToken = 0
    @State private var photoItem: PhotosPickerItem?
    @State private var inserting = false
    @State private var columnVisibility: NavigationSplitViewVisibility = {
        #if os(iOS)
        .detailOnly
        #else
        .all
        #endif
    }()
    private var ink: String { tool == .pencil ? pencilInk : penInk }
    private var width: Double { tool == .pencil ? pencilWidth : penWidth }
    private var pending: InkStroke? {
        get { liveInk.stroke }
        nonmutating set { liveInk.stroke = newValue }
    }
    @State private var selection = PageSelection()
    @State private var selectionPage: UUID?
    @State private var lassoPoints: [InkPoint] = []
    @State private var movingSelection = false
    @State private var selectedText: UUID?
    @State private var startPoint: InkPoint?
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("PAGES").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                    Spacer()
                    Button(action: addPage) { Image(systemName: "plus") }.buttonStyle(.borderless)
                        .help("Add page").accessibilityLabel("Add page")
                }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 10)
                List(selection: Binding(get: { selectedPage }, set: { id in
                    clearSelection(); navigationToken += 1; selectedPage = id
                    viewport.showPage(pageIndex, in: canvasSize); scrollOverflow = 0
                })) {
                    ForEach(Array(document.notebook.pages.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            PaperCanvas(page: item, pending: nil, selection: nil, erased: [], assets: document.notebook.assets ?? [])
                                .equatable().frame(width: 42, height: 56).clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.gray.opacity(0.2)))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Page \(index + 1)").font(.system(size: 13, weight: .medium))
                                Text(item.paper.rawValue + " paper").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(.vertical, 6).tag(item.id)
                    }
                }.listStyle(.sidebar)

            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                tools.padding(.horizontal, 18).padding(.vertical, 12).zIndex(1)
                Divider()
                GeometryReader { proxy in
                    notebookCanvas(size: proxy.size)
                        .onAppear { canvasSize = proxy.size }
                        .onChange(of: proxy.size) { _, size in
                            finish(false); canvasSize = size; viewport.clamp(in: size); revealText()
                        }
                }
                if selectedText != nil { textSelectionControls }
                HStack {
                    Text("\(pageIndex + 1) / \(document.notebook.pages.count)")
                    Spacer()
                    if inserting { ProgressView().controlSize(.small) }
                    Button("\(Int(zoom * 100))%") { fitCurrentPage() }.accessibilityLabel("Fit page")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 6)

            }
            .navigationTitle(document.notebook.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if let onClose { Button("Notebooks") { clearSelection(); onClose() } }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Rename notebook") { titleDraft = document.notebook.title; showTitle = true }
                        Button("Duplicate page", action: duplicatePage)
                        Button("Move page earlier") { reorder(-1) }.disabled(pageIndex == 0)
                        Button("Move page later") { reorder(1) }.disabled(pageIndex == document.notebook.pages.count - 1)
                        Button("Delete page", role: .destructive) { showDelete = true }.disabled(document.notebook.pages.count == 1)
                        Divider()
                        Button("Page templates…") { templateForNewPage = false; showTemplates = true }
                        Toggle("Add pages as you scroll", isOn: $automaticallyAddPages)
                        #if os(iOS)
                        Toggle("Apple Pencil only", isOn: $pencilOnly)
                        #endif
                        Button("Storage & other devices") { clearSelection(); showStorage = true }
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
                backedUpForModernEdit = false; gestureBefore = nil; pendingTextEdit = nil; textEdit = nil; undoStack = []; redoStack = []; clearSelection()
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

        .photosPicker(isPresented: $showPhotoLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }; clearSelection(); inserting = true
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadUnknown) }
                    let asset = try await Task.detached { try NotebookTransfer.photo(data) }.value
                    try insertImage(asset)
                } catch { recoveryMessage = error.localizedDescription; showRecovery = true }
                inserting = false; photoItem = nil
            }
        }
        .fileImporter(isPresented: $showImageFile, allowedContentTypes: [.png, .jpeg]) { result in
            guard case .success(let url) = result else { return }; inserting = true
            Task {
                do {
                    let imported = try await Task.detached { try NotebookTransfer.read(url) }.value
                    guard let asset = imported.assets?.first else { throw CocoaError(.fileReadCorruptFile) }
                    try insertImage(asset)
                } catch { recoveryMessage = error.localizedDescription; showRecovery = true }
                inserting = false
            }
        }
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
        .disabled(inserting)
        .sheet(isPresented: $showTransferExport) { NotebookExportSheet(notebook: document.notebook) }
        .sheet(isPresented: $showTransferImport) {
            NotebookImportSheet(allowNotebooks: false) { imported in
                try NotebookStorage.backup(document.notebook)
                remember(); clearSelection()
                let first = document.notebook.pages.count
                document.notebook.appendImported(imported)
                selectedPage = document.notebook.pages[first].id
                viewport.pageCount = document.notebook.pages.count; viewport.showPage(first, in: canvasSize)
            }
        }
        .sheet(isPresented: $showStorage) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Notebook storage").font(.title2)
                Label(NotebookStorage.location(fileURL), systemImage: "folder")
                if let fileURL { Text(fileURL.lastPathComponent).font(.caption) }
                Text(storageStatus).foregroundStyle(.secondary)
                Text("Keep notes on this device without an account. To use the same editable notebook elsewhere, choose a location in Files such as Google Drive or iCloud Drive. Install and sign into your chosen drive separately. Wait for its uploads before switching devices.")
                if let onMove {
                    Button("Move notebook…") { showStorage = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onMove() } }.buttonStyle(.borderedProminent)
                } else {
                    #if os(macOS)
                    Button("Move notebook…") {
                        showStorage = false
                        if let fileURL, let native = NSDocumentController.shared.document(for: fileURL) {
                            do { try NotebookStorage.backup(document.notebook); native.move(nil) }
                            catch { recoveryMessage = error.localizedDescription; showRecovery = true }
                        }
                    }.disabled(fileURL == nil)
                    #endif
                }
                Button("Export a separate copy…") { showStorage = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showTransferExport = true } }
                Text("A move changes the working file’s location. An export makes an independent copy. Cloud status and conflict behavior depend on the provider; simultaneous editing is not supported.").font(.caption).foregroundStyle(.secondary)
                Button("Done") { showStorage = false }
            }.padding(28).frame(idealWidth: 500)
        }
    }

    private func notebookCanvas(size: CGSize) -> some View {
        let scale = viewport.scale(in: size)
        return ZStack(alignment: .topLeading) {
            Color(red: 0.92, green: 0.93, blue: 0.91)
            ForEach(Array(document.notebook.pages.enumerated()), id: \.element.id) { index, item in
                let origin = viewport.pageOrigin(at: index, in: size)
                if origin.y < size.height && origin.y + 1024 * scale > 0 {
                    ZStack(alignment: .topLeading) {
                        let displayed = gesturePage == item.id ? (gesturePreview ?? item) : item
                        PaperCanvas(page: displayed, pending: nil,
                                    selection: nil, erased: gesturePage == item.id ? erasedIDs : [],
                                    editingText: textEdit?.pageID == item.id ? textEdit?.id : nil, assets: document.notebook.assets ?? []).equatable()
                        if gesturePage == item.id { LiveInkCanvas(ink: liveInk) }
                        if selectionPage == item.id {
                            SelectionOverlay(page: displayed, selection: selection, lasso: lassoPoints, scale: scale)
                        }

                    }
                    .frame(width: 768 * scale, height: 1024 * scale)
                    .clipped().shadow(color: .black.opacity(0.09), radius: 12, y: 5)
                    .offset(x: origin.x, y: origin.y).allowsHitTesting(false)
                }
            }
            PointerSurface(pencilOnly: pencilOnly && (tool == .pen || tool == .pencil || tool == .eraser), panMode: panMode, inputKey: "\(tool)-\(panMode)-\(pencilOnly)-\(toolPopover != nil)-\(showTransferExport)-\(showImageFile)-\(showPhotoLibrary)-\(inserting)-\(navigationToken)",
                began: { point in
                    guard let index = viewport.pageIndex(at: point, in: size), document.notebook.pages.indices.contains(index) else { return }
                    let pageID = document.notebook.pages[index].id
                    if tool != .select || selectionPage != pageID { clearSelection() }
                    selectedPage = pageID
                    begin(viewport.pagePoint(point, at: index, in: size))
                },
                moved: {
                    guard let index = document.notebook.pages.firstIndex(where: { $0.id == gesturePage }) else { return }
                    let p = viewport.pagePoint($0, at: index, in: size)
                    move(InkPoint(x: min(768, max(0, p.x)), y: min(1024, max(0, p.y)), pressure: p.pressure))
                }, ended: finish,
                panned: { scrollPages($0, size: size, momentum: $1) },
                magnified: { viewport.magnify($0, at: $1, in: size); scrollOverflow = 0 },
                pencilTapped: {
                    clearSelection(); panMode = false
                    if tool == .eraser { tool = previousWritingTool }
                    else { previousWritingTool = tool; tool = .eraser }
                })
                // Zoom changes page geometry, never the native input view bounds.
                .frame(width: size.width, height: size.height)
            if let target = textEdit,
               let index = document.notebook.pages.firstIndex(where: { $0.id == target.pageID }) {
                let origin = viewport.pageOrigin(at: index, in: size)
                InlineTextEditor(initialText: target.text, fontSize: editingCard(target).size) { value in updateText(value, target: target) }
                    .id(target.id)
                    .frame(width: editingCard(target).width, height: editingCard(target).height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: origin.x + target.x * scale, y: origin.y + target.y * scale)
            }
            if tool == .select, selection.count > 0, gestureBefore == nil,
               let index = document.notebook.pages.firstIndex(where: { $0.id == selectionPage }),
               let bounds = selection.bounds(in: document.notebook.pages[index]) {
                let origin = viewport.pageOrigin(at: index, in: size)
                selectionActions
                    .position(x: min(size.width-110, max(110, origin.x + bounds.midX*scale)),
                              y: min(size.height-26, max(26, origin.y + bounds.minY*scale-30)))
            }
        }.frame(width: size.width, height: size.height)
            .contentShape(Rectangle()).clipped()
    }
    private func scrollPages(_ delta: CGSize, size: CGSize, momentum: Bool = false) {
        if textEdit != nil { clearSelection() }
        let overflow = viewport.pan(delta, in: size)
        if !momentum && delta.height < 0 && overflow > 0 { scrollOverflow += overflow }
        else if delta.height != 0 { scrollOverflow = 0 }
        if !momentum && automaticallyAddPages && scrollOverflow >= 72, let last = document.notebook.pages.last {
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
        finish(false); navigationToken += 1; viewport = NotebookViewport(pageCount: document.notebook.pages.count)
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
        finish(false); navigationToken += 1
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
            HStack(spacing: 12) { historyControls; Spacer(minLength: 8); toolPicker; Spacer(minLength: 8); insertControls }
            VStack(spacing: 4) {
                HStack { historyControls; Spacer(); insertControls }
                toolPicker
            }
        }
    }
    private var toolPicker: some View {
        HStack(spacing: 3) {
            ForEach(EditorTool.allCases, id: \.self) { item in
                Button {
                    if tool == item && !panMode { finish(false); toolPopover = item }
                    else { clearSelection(); panMode = false; tool = item; toolPopover = nil }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol).font(.system(size: 19))
                        if item == .pen || item == .pencil {
                            Capsule().fill(inkColor(item == .pen ? penInk : pencilInk)).frame(width: 18, height: 3)
                        }
                    }.frame(width: 44, height: 44)
                        .foregroundStyle(tool == item && !panMode ? accent : .secondary)
                        .background(tool == item && !panMode ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).help(item.rawValue).accessibilityLabel(item.rawValue)
                    .accessibilityAddTraits(tool == item && !panMode ? [.isSelected] : [])
                    .popover(isPresented: Binding(get: { toolPopover == item }, set: { if !$0 { toolPopover = nil } }), arrowEdge: .top) {
                        toolSettings(item).presentationCompactAdaptation(.popover)
                    }
            }
            #if os(macOS)
            Button { clearSelection(); panMode.toggle() } label: { Image(systemName: "hand.draw").frame(width: 44, height: 44) }
                .buttonStyle(.plain).foregroundStyle(panMode ? accent : .secondary).accessibilityLabel("Hand")
            #endif
        }
    }
    private func toolSettings(_ item: EditorTool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(item.rawValue).font(.headline); Spacer(); Button("Done") { toolPopover = nil } }
            if item == .pen || item == .pencil {
                let color = Binding(get: { item == .pencil ? pencilInk : penInk }, set: { if item == .pencil { pencilInk = $0 } else { penInk = $0 } })
                let thickness = Binding(get: { item == .pencil ? pencilWidth : penWidth }, set: { if item == .pencil { pencilWidth = $0 } else { penWidth = $0 } })
                HStack(spacing: 10) {
                    ForEach(["ink", "blue", "red", "green", "gold", "purple"], id: \.self) { name in
                        Button { color.wrappedValue = name } label: {
                            Circle().fill(inkColor(name)).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.primary, lineWidth: color.wrappedValue == name ? 2 : 0).padding(-3))
                        }.buttonStyle(.plain).accessibilityLabel("\(name) ink")
                    }
                }
                Text("Thickness").font(.subheadline)
                Slider(value: thickness, in: 1...12, step: 0.5).accessibilityLabel("Stroke thickness")
                StrokePreview(color: color.wrappedValue, width: thickness.wrappedValue, pencil: item == .pencil).frame(height: 46)
            } else if item == .eraser {
                Picker("Erase", selection: $eraseWholeStroke) { Text("Part of stroke").tag(false); Text("Whole stroke").tag(true) }.pickerStyle(.segmented)
                Text("Eraser size").font(.subheadline)
                Slider(value: $eraserRadius, in: 4...36, step: 1).accessibilityLabel("Eraser size")
                Circle().fill(accent.opacity(0.1)).overlay(Circle().stroke(accent)).frame(width: eraserRadius*2, height: eraserRadius*2).frame(maxWidth: .infinity)
            } else if item == .select {
                Picker("Selection shape", selection: $rectangleSelection) { Text("Freehand").tag(false); Text("Rectangle").tag(true) }.pickerStyle(.segmented)
                Text("Circle or box content. Drag inside to move; drag the corner to resize.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Tap the page to type. Tap existing text to edit it. Use Selection to move it or adjust its width.").foregroundStyle(.secondary)
            }
        }.padding(20).frame(width: 310)
    }
    private var insertControls: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Image from Files…") { clearSelection(); showImageFile = true }
                Button("Photo Library…") { clearSelection(); showPhotoLibrary = true }
                Button("PDF or image pages…") { clearSelection(); showTransferImport = true }
                Button("Blank page…", action: addPage)
                Divider()
                Button("Paste selection", action: pasteSelection)
            } label: { Image(systemName: "plus.circle").font(.system(size: 21)).frame(width: 44, height: 44) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Insert")
            Button { clearSelection(); showTransferExport = true } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 20)).frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("Export")
        }
    }
    private var historyControls: some View {
        HStack(spacing: 12) {
            Button(action: undo) { Image(systemName: "arrow.uturn.backward").frame(width: 36, height: 44) }.disabled(undoStack.isEmpty).help("Undo").accessibilityLabel("Undo")
            Button(action: redo) { Image(systemName: "arrow.uturn.forward").frame(width: 36, height: 44) }.disabled(redoStack.isEmpty).help("Redo").accessibilityLabel("Redo")
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
        HStack {
            Text("Typing on page").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Move / resize") {
                let id = selectedText; clearSelection(); tool = .select
                if let id { selection = PageSelection(texts: [id]); selectionPage = page.id }
            }
            Button("Done") { clearSelection() }.keyboardShortcut(.escape, modifiers: [])
        }.padding(.horizontal, 16).padding(.vertical, 6)
    }
    private func editingCard(_ target: TextEditTarget) -> TextCard {
        document.notebook.pages.first(where: { $0.id == target.pageID })?.texts.first(where: { $0.id == target.id }) ?? target.card
    }
    private func revealText() {
        guard let target = textEdit, let index = document.notebook.pages.firstIndex(where: { $0.id == target.pageID }) else { return }
        let top = viewport.pageOrigin(at: index, in: canvasSize).y + target.y * viewport.scale(in: canvasSize)
        if top > canvasSize.height * 0.55 { viewport.pan(CGSize(width: 0, height: canvasSize.height*0.4-top), in: canvasSize) }
    }
    private func updateText(_ value: String, target: TextEditTarget) {
        guard let index = document.notebook.pages.firstIndex(where: { $0.id == target.pageID }) else { return }
        if value.isEmpty && !document.notebook.pages[index].texts.contains(where: { $0.id == target.id }) { return }
        guard document.notebook.pages[index].texts.first(where: { $0.id == target.id })?.text != value else { return }
        if !recordedTextUndo { remember(); recordedTextUndo = true }
        if !document.notebook.pages[index].texts.contains(where: { $0.id == target.id }), !value.isEmpty {
            var card = target.card; card.text = value
            document.notebook.pages[index].texts.append(card)
        } else { document.notebook.pages[index].updateText(id: target.id, text: value, x: target.x, y: target.y) }
        if let i = document.notebook.pages[index].texts.firstIndex(where: { $0.id == target.id }) {
            var card = document.notebook.pages[index].texts[i]
            card.boxWidth = card.width
            card.boxHeight = min(max(44, NotebookRenderer.textHeight(value, width: card.width-10, fontSize: card.size)), max(44, 1024-card.y))
            document.notebook.pages[index].texts[i] = card
        }
        selectedText = target.id
    }
    private var helpView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Make yourself a little space.").font(.system(size: 28, weight: .medium, design: .serif))
            Text("Noted · First prototype").font(.subheadline).foregroundStyle(.secondary)
            Label("Your notes, on your device.", systemImage: "pencil.and.outline")
            Text("Tap a tool to select it; tap it again for settings. Pen and Pencil remember their own color and thickness. Eraser removes part of a stroke or the whole stroke. Selection supports freehand or rectangle: drag inside to move and drag the corner to resize. Tap the page with Text to type; choose Move / resize to adjust it. Two fingers pan and pinch on iPad. On Mac, use the trackpad or Hand. Insert adds an image, PDF pages or a blank page. Double-tap a supported Pencil to switch eraser (unless disabled in system settings). Apple Pencil only is in the notebook menu.")
            Label("One editable .noted file", systemImage: "doc.badge.arrow.up")
            Text("Use the system document controls to save, open, or move your notebook. Local storage needs no account. Optionally move the notebook to a Files location such as Google Drive or iCloud Drive. Wait for your provider to upload changes before switching devices; use Recover file versions to export system-reported conflicts and retained reload copies. Conflicts are left unresolved; automatic conflict merging is not implemented. A sequential handoff has been reported working; concurrent editing and recovery still need testing.")
            Text("No account with Noted, ads, subscriptions, or hosted backend. Your chosen drive’s storage limits still apply. PDF and image imports become backgrounds; handwriting recognition is not included.")
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

    private var selectionActions: some View {
        HStack(spacing: 4) {
            Button(action: copySelection) { Image(systemName: "doc.on.doc").frame(width: 44, height: 40) }.accessibilityLabel("Copy selection").keyboardShortcut("c", modifiers: .command)
            Button { placeSelection(selection.contents(of: page), assets: document.notebook.assets ?? []) } label: { Image(systemName: "plus.square.on.square").frame(width: 44, height: 40) }.accessibilityLabel("Duplicate selection")
            Button {
                remember(); document.notebook.pages[pageIndex] = selection.removing(from: page); clearSelection()
            } label: { Image(systemName: "trash").frame(width: 44, height: 40) }.accessibilityLabel("Delete selection")
            Button { clearSelection() } label: { Image(systemName: "xmark").frame(width: 36, height: 40) }.accessibilityLabel("Deselect")
        }.buttonStyle(.plain).padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).shadow(radius: 3, y: 2)
    }
    private func reflowSelectedText(at index: Int) {
        for i in document.notebook.pages[index].texts.indices where selection.texts.contains(document.notebook.pages[index].texts[i].id) {
            var card = document.notebook.pages[index].texts[i]
            card.boxHeight = min(1024-card.y, max(44, NotebookRenderer.textHeight(card.text, width: card.width-10, fontSize: card.size)))
            document.notebook.pages[index].texts[i] = card
        }
    }
    private func copySelection() {
        let selected = selection.contents(of: page)
        let book = Notebook(title: "Selection", pages: [selected], assets: document.notebook.assets).selectingPages([0])
        do { SelectionClipboard.write(try book.encoded()) }
        catch { recoveryMessage = error.localizedDescription; showRecovery = true }
    }
    private func pasteSelection() {
        clearSelection()
        do {
            if let data = SelectionClipboard.read() {
                let book = try Notebook.decode(data); try NotebookTransfer.validate(book)
                guard let contents = book.pages.first else { return }
                placeSelection(contents, assets: book.assets ?? [])
            } else if let data = SelectionClipboard.image() { try insertImage(NotebookTransfer.photo(data)) }
            else { recoveryMessage = "Copy a selection in Noted or an image, then paste it here."; showRecovery = true }
        } catch { recoveryMessage = error.localizedDescription; showRecovery = true }
    }
    private func placeSelection(_ contents: NotePage, assets: [NotebookAsset]) {
        do { try NotebookStorage.backup(document.notebook) }
        catch { recoveryMessage = error.localizedDescription; showRecovery = true; return }
        remember(); clearSelection()
        var copy = contents
        var remap: [UUID: UUID] = [:]
        let used = Set((contents.images ?? []).map(\.assetID))
        for original in assets where used.contains(original.id) {
            if let existing = document.notebook.assets?.first(where: { $0.kind == original.kind && $0.data == original.data }) { remap[original.id] = existing.id }
            else {
                var asset = original; asset.id = UUID(); remap[original.id] = asset.id
                document.notebook.assets = (document.notebook.assets ?? []) + [asset]
            }
        }
        copy.strokes = copy.strokes.map { var item = $0; item.id = UUID(); return item }
        copy.texts = copy.texts.map { var item = $0; item.id = UUID(); return item }
        copy.images = copy.images?.map { var item = $0; item.id = UUID(); item.assetID = remap[item.assetID] ?? item.assetID; return item }
        let selected = PageSelection(strokes: Set(copy.strokes.map(\.id)), texts: Set(copy.texts.map(\.id)), images: Set((copy.images ?? []).map(\.id)))
        copy = selected.moving(copy, by: CGSize(width: 24, height: 24))
        document.notebook.pages[pageIndex].strokes += copy.strokes
        document.notebook.pages[pageIndex].texts += copy.texts
        if let images = copy.images { document.notebook.pages[pageIndex].images = (page.images ?? []) + images }
        tool = .select; panMode = false; selection = selected; selectionPage = page.id
    }
    private func insertImage(_ asset: NotebookAsset) throws {
        guard asset.kind != .pdf, let image = NotebookRenderer.objectImage(asset) else { throw CocoaError(.fileReadCorruptFile) }
        try NotebookStorage.backup(document.notebook)
        remember(); clearSelection()
        let factor = min(480/Double(image.width), 600/Double(image.height))
        let width = Double(image.width)*factor, height = Double(image.height)*factor
        let item = PlacedImage(assetID: asset.id, x: (768-width)/2, y: (1024-height)/2, width: width, height: height)
        document.notebook.assets = (document.notebook.assets ?? []) + [asset]
        document.notebook.pages[pageIndex].images = (page.images ?? []) + [item]
        tool = .select; panMode = false; selection = PageSelection(images: [item.id]); selectionPage = page.id
    }

    private func begin(_ p: InkPoint) {
        guard (0...768).contains(p.x), (0...1024).contains(p.y) else { return }
        finish(false)
        if tool != .select { clearSelection() }
        if !backedUpForModernEdit && document.notebook.version < 3 && (tool == .pencil || tool == .text || tool == .select) {
            do { try NotebookStorage.backup(document.notebook); backedUpForModernEdit = true }
            catch { recoveryMessage = "A safety copy couldn’t be saved: \(error.localizedDescription)"; showRecovery = true; return }
        }
        gestureBefore = document.notebook; gesturePage = page.id; startPoint = p
        switch tool {
        case .pen, .pencil:
            pending = InkStroke(points: [p], color: ink, width: width, pencil: tool == .pencil ? true : nil)
        case .eraser: erase(p)
        case .select:
            textEdit = nil; selectedText = nil
            let bounds = selection.bounds(in: page)
            resizingSelection = selectionPage == page.id && bounds.map { hypot(p.x-$0.maxX, p.y-$0.maxY) < 22/viewport.scale(in: canvasSize) } == true
            movingSelection = !resizingSelection && selectionPage == page.id &&
                (selection.bounds(in: page)?.insetBy(dx: -8, dy: -8).contains(CGPoint(x: p.x, y: p.y)) ?? false)
            if !movingSelection && !resizingSelection { selection = PageSelection(); lassoPoints = [p] }
            selectionPage = page.id
        case .text:
            let card = page.text(at: p) ?? TextCard(x: min(p.x, 700), y: min(p.y, 960), boxWidth: min(300, 768-min(p.x, 700)), boxHeight: 44)
            pendingTextEdit = TextEditTarget(pageID: page.id, card: card)
        }
    }
    private func move(_ p: InkPoint) {
        guard let startPoint else { return }
        switch tool {
        case .pen, .pencil: liveInk.stroke?.points.append(p)
        case .eraser: erase(p)
        case .select:
            if let original = gestureBefore?.pages.first(where: { $0.id == gesturePage }), movingSelection || resizingSelection {
                gesturePreview = resizingSelection ? selection.resizing(original, to: p) : selection.moving(original, by: CGSize(width: p.x - startPoint.x, height: p.y - startPoint.y))
            } else if rectangleSelection {
                lassoPoints = [startPoint, InkPoint(x: p.x, y: startPoint.y), p, InkPoint(x: startPoint.x, y: p.y)]
            } else if let last = lassoPoints.last, hypot(p.x - last.x, p.y - last.y) >= 2 { lassoPoints.append(p) }
        case .text: break
        }
    }
    private func erase(_ p: InkPoint) {
        let previous = lastErase ?? p
        let steps = max(1, Int(ceil(hypot(p.x-previous.x, p.y-previous.y)/max(2, eraserRadius/2))))
        var preview = gesturePreview ?? page
        for step in 1...steps {
            let t = Double(step)/Double(steps)
            let center = InkPoint(x: previous.x + (p.x-previous.x)*t, y: previous.y + (p.y-previous.y)*t)
            if eraseWholeStroke { preview.strokes.removeAll { $0.distance(to: center) < eraserRadius+$0.width/2 } }
            else { preview.strokes = preview.strokes.flatMap { $0.erasing(at: center, radius: eraserRadius) } }
        }
        gesturePreview = preview; lastErase = p
    }
    private func finish(_ cancelled: Bool) {
        guard gestureBefore != nil else { return }
        if cancelled {
            if let gestureBefore { document.notebook = gestureBefore }; selection = PageSelection(); selectedText = nil
        } else {
            if let index = document.notebook.pages.firstIndex(where: { $0.id == gesturePage }) {
                if let gesturePreview {
                    document.notebook.pages[index] = gesturePreview
                    if resizingSelection { reflowSelectedText(at: index) }
                }
                if tool == .select && !movingSelection && !resizingSelection {
                    selection = LassoRegion(points: lassoPoints).selection(in: document.notebook.pages[index])
                    selectionPage = gesturePage
                }
                if let pending { document.notebook.pages[index].strokes.append(pending) }
                document.notebook.pages[index].strokes.removeAll { erasedIDs.contains($0.id) }
            }
            if let gestureBefore, gestureBefore != document.notebook {
                pushUndo(gestureBefore)
            }
        }
        let edit = cancelled ? nil : pendingTextEdit
        pendingTextEdit = nil
        pending = nil; startPoint = nil; lassoPoints = []; movingSelection = false; resizingSelection = false; gestureBefore = nil; gesturePreview = nil; lastErase = nil; erasedIDs = []
        if let edit { recordedTextUndo = false; selectedText = edit.id; textEdit = edit; revealText() }
    }
    private func clearSelection() {
        finish(false)
        if let target = textEdit, let index = document.notebook.pages.firstIndex(where: { $0.id == target.pageID }) {
            document.notebook.pages[index].texts.removeAll { $0.id == target.id && $0.text.isEmpty }
        }
        textEdit = nil
        selection = PageSelection(); selectionPage = nil; lassoPoints = []; movingSelection = false
        selectedText = nil; pending = nil; startPoint = nil
        erasedIDs = []; gestureBefore = nil; gesturePreview = nil; lastErase = nil; resizingSelection = false; pendingTextEdit = nil
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
    case "purple": Color(red: 0.48, green: 0.28, blue: 0.66)
    default: Color(red: 0.18, green: 0.22, blue: 0.23)
    }
}

struct PaperCanvas: View, Equatable {
    var page: NotePage
    var pending: InkStroke?
    var selection: UUID?
    var erased: Set<UUID>
    var editingText: UUID? = nil
    var assets: [NotebookAsset] = []
    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                cg.scaleBy(x: size.width/768, y: size.height/1024)
                var visible = page
                visible.strokes.removeAll { erased.contains($0.id) }
                visible.texts.removeAll { $0.id == editingText }
                if let pending { visible.strokes.append(pending) }
                NotebookRenderer.draw(page: visible, assets: assets, paper: true, in: cg, preview: true)
            }
        }.accessibilityLabel("Notebook page, \(page.strokes.count) strokes, \(page.texts.count) text items, \((page.images ?? []).count) images")
    }
}

private final class LiveInk: ObservableObject { @Published var stroke: InkStroke? }
private struct LiveInkCanvas: View {
    @ObservedObject var ink: LiveInk
    var body: some View {
        Canvas { context, size in
            if let stroke = ink.stroke {
                context.withCGContext { cg in
                    cg.scaleBy(x: size.width/768, y: size.height/1024); NotebookRenderer.drawStroke(stroke, in: cg)
                }
            }
        }.allowsHitTesting(false)
    }
}
private struct StrokePreview: View {
    let color: String
    let width: Double
    let pencil: Bool
    var body: some View {
        Canvas { context, size in
            var points: [InkPoint] = []
            for i in 0...60 {
                let t = Double(i)
                let x = t * Double(size.width) / 60.0
                let y = Double(size.height)/2.0 + sin(t/10.0)*10.0
                points.append(InkPoint(x: x, y: y, pressure: 0.3+t/100.0))
            }
            context.withCGContext { NotebookRenderer.drawStroke(InkStroke(points: points, color: color, width: width, pencil: pencil ? true : nil), in: $0) }
        }
    }
}

private struct TextEditTarget: Identifiable {
    let id: UUID
    let pageID: UUID
    let card: TextCard
    let text: String
    let x: Double
    let y: Double
    init(pageID: UUID, card: TextCard) {
        self.card = card; self.pageID = pageID; id = card.id; text = card.text; x = card.x; y = card.y
    }
}

private struct InlineTextEditor: View {
    @FocusState private var focused: Bool
    @State private var text: String
    var fontSize: Double
    var onEdit: (String) -> Void
    init(initialText: String, fontSize: Double, onEdit: @escaping (String) -> Void) {
        _text = State(initialValue: initialText); self.fontSize = fontSize; self.onEdit = onEdit
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: fontSize)).foregroundStyle(inkColor("ink"))
                .scrollContentBackground(.hidden)
                .focused($focused).accessibilityLabel("Text on page")
            if text.isEmpty {
                Text("Type here…").font(.system(size: 20)).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 8).allowsHitTesting(false)
            }
        }
        .background(.clear)
        .onChange(of: text) { _, value in onEdit(value) }
        .task { focused = true }
    }
}

private struct SelectionOverlay: View {
    let page: NotePage
    let selection: PageSelection
    let lasso: [InkPoint]
    let scale: Double

    var body: some View {
        Canvas { context, _ in
            if let bounds = selection.bounds(in: page) {
                let rect = CGRect(x: bounds.minX * scale - 4, y: bounds.minY * scale - 4,
                                  width: bounds.width * scale + 8, height: bounds.height * scale + 8)
                let box = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(box, with: .color(inkColor("green").opacity(0.06)))
                context.stroke(box, with: .color(inkColor("green")), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                let handle = Path(ellipseIn: CGRect(x: bounds.maxX*scale-7, y: bounds.maxY*scale-7, width: 14, height: 14))
                context.fill(handle, with: .color(.white)); context.stroke(handle, with: .color(inkColor("green")), lineWidth: 2)
            }
            if let first = lasso.first {
                var path = Path()
                path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
                for point in lasso.dropFirst() { path.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale)) }
                path.closeSubpath()
                context.fill(path, with: .color(inkColor("green").opacity(0.08)))
                context.stroke(path, with: .color(inkColor("green")), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
        }.allowsHitTesting(false)
    }
}


private enum SelectionClipboard {
    static let type = "app.noted.selection"
    static func write(_ data: Data) {
        #if os(iOS)
        UIPasteboard.general.setData(data, forPasteboardType: type)
        #else
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .init(type))
        #endif
    }
    static func read() -> Data? {
        #if os(iOS)
        UIPasteboard.general.data(forPasteboardType: type)
        #else
        NSPasteboard.general.data(forType: .init(type))
        #endif
    }
    static func image() -> Data? {
        #if os(iOS)
        UIPasteboard.general.image?.pngData()
        #else
        NSImage(pasteboard: .general)?.tiffRepresentation
        #endif
    }
}
