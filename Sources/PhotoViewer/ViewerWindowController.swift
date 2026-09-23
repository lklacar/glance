import AppKit
import PhotoViewerCore

final class FileMonitor {
    private var source: DispatchSourceFileSystemObject?
    init?(url: URL, handler: @escaping () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        self.source = source; source.resume()
    }
    deinit { source?.cancel() }
}

final class ViewerWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let canvas = CanvasView(frame: .zero)
    private let status = NSTextField(labelWithString: "Scroll to zoom  ·  ← → to browse")
    private let position = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let zoomButton = NSButton(title: "Fit", target: nil, action: nil)
    private var buttons: [String: NSButton] = [:]
    private(set) var catalog = FolderCatalog()
    private var folder: URL?
    private var decoded: DecodedImage?
    private let decodeQueue = OperationQueue()
    private let scanQueue = DispatchQueue(label: "PhotoViewer.folder", qos: .userInitiated)
    private var requestID = UUID()
    private var folderID = UUID()
    private var animationID = UUID()
    private var scanID = UUID()
    private var animationPaused = false
    private var animationTimer: Timer?
    private var frameIndex = 0
    private var folderMonitor: FileMonitor?
    private var fileMonitor: FileMonitor?
    private var refreshWork: DispatchWorkItem?
    private var slideshow: Timer?
    private var folderWarning: String?
    private var isClosed = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Photo Viewer"
        window.minSize = NSSize(width: 560, height: 380)
        window.setFrameAutosaveName("PhotoViewer.MainWindow")
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.delegate = self
        decodeQueue.name = "PhotoViewer.decoder"; decodeQueue.maxConcurrentOperationCount = 1
        decodeQueue.qualityOfService = .userInitiated
        buildContent()
        let toolbar = NSToolbar(identifier: "ViewerToolbar")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        canvas.onOpen = { [weak self] in self?.openDocument(nil) }
        canvas.onDrop = { [weak self] in self?.open($0) }
        canvas.onNavigate = { [weak self] in self?.navigate($0) }
        canvas.onZoom = { [weak self] in self?.updateStatus() }
        canvas.onTogglePlayback = { [weak self] in self?.togglePlayback(nil) }
        canvas.onEscape = { [weak self] in
            guard let self else { return }
            stopSlideshow()
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
        if !window.setFrameUsingName("PhotoViewer.MainWindow") { window.center() }
        updateStatus()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let footer = NSView(); footer.wantsLayer = true
        footer.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
        for view in [canvas, footer] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        position.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        position.textColor = .secondaryLabelColor
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        for view in [status, position, progress] { view.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(view) }
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor), canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor), footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 30),
            status.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16), status.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            position.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16), position.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            progress.trailingAnchor.constraint(equalTo: position.leadingAnchor, constant: -10), progress.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            progress.widthAnchor.constraint(equalToConstant: 16), progress.heightAnchor.constraint(equalToConstant: 16),
            status.trailingAnchor.constraint(lessThanOrEqualTo: progress.leadingAnchor, constant: -12)
        ])
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [NSToolbarItem.Identifier("open"), NSToolbarItem.Identifier("previous"), NSToolbarItem.Identifier("next"), .flexibleSpace]
        + ["zoomOut", "zoom", "zoomIn", "rotate", "play", "info", "fullscreen"].map { NSToolbarItem.Identifier($0) }
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        let definitions: [String: (String, String, Selector)] = [
            "open": ("folder", "Open image or folder (⌘O)", #selector(openDocument(_:))),
            "previous": ("chevron.left", "Previous image (←)", #selector(previous(_:))),
            "next": ("chevron.right", "Next image (→)", #selector(next(_:))),
            "zoomOut": ("minus.magnifyingglass", "Zoom out (−)", #selector(zoomOut(_:))),
            "zoomIn": ("plus.magnifyingglass", "Zoom in (+)", #selector(zoomIn(_:))),
            "rotate": ("rotate.right", "Rotate view clockwise (⌘R)", #selector(rotate(_:))),
            "play": ("play", "Start or stop slideshow (⇧⌘P)", #selector(toggleSlideshow(_:))),
            "info": ("info.circle", "Image information (⌘I)", #selector(showInfo(_:))),
            "fullscreen": ("arrow.up.left.and.arrow.down.right", "Toggle full screen (⌃⌘F)", #selector(toggleFullScreen(_:)))
        ]
        if id.rawValue == "zoom" {
            zoomButton.target = self; zoomButton.action = #selector(fit(_:)); zoomButton.bezelStyle = .texturedRounded
            zoomButton.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            zoomButton.toolTip = "Fit image to window (0)"; zoomButton.setAccessibilityLabel("Zoom level. Click to fit image")
            zoomButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
            item.view = zoomButton; item.label = "Zoom"; item.target = self; item.action = #selector(fit(_:)); return item
        }
        guard let (symbol, label, action) = definitions[id.rawValue] else { return nil }
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: action)
        button.bezelStyle = .texturedRounded; button.toolTip = label; button.setAccessibilityLabel(label)
        item.view = button; item.label = label; item.target = self; item.action = action; buttons[id.rawValue] = button
        return item
    }

    func open(_ input: URL) {
        guard input.isFileURL else { return }
        isClosed = false
        showWindow(nil); window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(canvas)
        stopSlideshow()
        let url = input.standardizedFileURL
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let newFolder = isDirectory.boolValue ? url : url.deletingLastPathComponent()
        folder = newFolder; folderID = UUID(); folderWarning = nil
        refreshWork?.cancel(); folderMonitor = nil; fileMonitor = nil
        catalog = FolderCatalog(urls: isDirectory.boolValue ? [] : [url], selecting: url)
        folderMonitor = FileMonitor(url: newFolder) { [weak self] in self?.scheduleRefresh() }
        if isDirectory.boolValue {
            cancelDecoding(); decoded = nil
            canvas.showMessage("Opening folder…", detail: newFolder.lastPathComponent)
        } else { loadCurrent() }
        scanFolder(initial: true)
    }

    private func scanFolder(initial: Bool = false) {
        guard let folder else { return }
        let folderToken = folderID, token = UUID(); scanID = token
        scanQueue.async { [weak self] in
            let result = Result { try FolderCatalog.scan(folder) }
            DispatchQueue.main.async {
                guard let self, folderToken == self.folderID, token == self.scanID, !self.isClosed else { return }
                switch result {
                case .success(var urls):
                    // An explicitly opened hidden or extensionless image is still viewable.
                    if let current = self.catalog.current, !urls.contains(current), FileManager.default.fileExists(atPath: current.path) {
                        urls.append(current)
                        urls.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    }
                    let before = self.catalog.current
                    self.catalog.refresh(urls)
                    if self.catalog.current != before || (self.decoded == nil && before == nil) { self.loadCurrent() }
                    self.folderWarning = nil
                case .failure(let error):
                    self.folderWarning = "Folder unavailable: \(error.localizedDescription)"
                    if self.catalog.current == nil {
                        self.canvas.showMessage("Couldn’t read this folder", detail: error.localizedDescription)
                    }
                }
                self.updateStatus()
            }
        }
    }
    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanFolder() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    private func cancelDecoding() {
        requestID = UUID(); animationID = UUID(); decodeQueue.cancelAllOperations()
        animationTimer?.invalidate(); animationTimer = nil
        progress.stopAnimation(nil)
    }
    private func loadCurrent() {
        cancelDecoding(); decoded = nil; animationPaused = false; frameIndex = 0; fileMonitor = nil
        guard let url = catalog.current else {
            stopSlideshow(); window?.title = "Photo Viewer"; window?.representedURL = nil
            canvas.showMessage("No images in this folder", detail: "Open another image or folder with ⌘O")
            updateStatus(); return
        }
        let token = requestID
        window?.title = url.lastPathComponent; window?.representedURL = url
        canvas.showMessage("", detail: "")
        progress.startAnimation(nil); updateStatus()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard operation?.isCancelled == false else { return }
            let result = autoreleasepool { Result { try ImageDecoder.load(url) } }
            guard operation?.isCancelled == false else { return }
            DispatchQueue.main.async {
                guard let self, token == self.requestID, !self.isClosed else { return }
                self.progress.stopAnimation(nil)
                switch result {
                case .success(let image):
                    self.decoded = image; self.canvas.display(image)
                    self.canvas.setAccessibilityValue("\(url.lastPathComponent), \(Int(image.pixelSize.width)) by \(Int(image.pixelSize.height)) pixels")
                    NSDocumentController.shared.noteNewRecentDocumentURL(url)
                    self.animateNext()
                case .failure(let error):
                    self.canvas.showMessage("Couldn’t display this image", detail: error.localizedDescription)
                }
                self.fileMonitor = FileMonitor(url: url) { [weak self] in
                    guard let self else { return }
                    self.scheduleFileReload()
                }
                self.updateStatus()
            }
        }
        decodeQueue.addOperation(operation)
    }
    private var reloadWork: DispatchWorkItem?
    private func scheduleFileReload() {
        reloadWork?.cancel()
        let token = requestID
        let work = DispatchWorkItem { [weak self] in
            guard let self, token == self.requestID, !self.isClosed else { return }
            if let url = self.catalog.current, FileManager.default.fileExists(atPath: url.path) { self.loadCurrent() }
            else { self.scanFolder() }
        }
        reloadWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    private func animateNext() {
        guard let decoded, decoded.frameCount > 1, !animationPaused, !isClosed, window?.isMiniaturized != true else { return }
        let token = animationID, index = frameIndex, next = (frameIndex + 1) % decoded.frameCount
        let start = Date()
        decodeQueue.addOperation { [weak self] in
            let delay = decoded.duration(at: index)
            let frame = autoreleasepool { decoded.frame(at: next) }
            DispatchQueue.main.async {
                guard let self, token == self.animationID, !self.animationPaused, !self.isClosed else { return }
                let timer = Timer(timeInterval: max(0.01, delay - Date().timeIntervalSince(start)), repeats: false) { [weak self] _ in
                    guard let self, token == self.animationID, !self.animationPaused, !self.isClosed else { return }
                    if let frame { self.canvas.image = frame; self.canvas.needsDisplay = true }
                    self.frameIndex = next; self.animateNext()
                }
                self.animationTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }
    private func updateStatus() {
        let hasImage = decoded != nil
        for (id, button) in buttons {
            button.isEnabled = ["open", "fullscreen"].contains(id) || (["previous", "next", "play"].contains(id) ? catalog.urls.count > 1 : hasImage)
        }
        zoomButton.isEnabled = hasImage
        let percent = canvas.viewport.scale * (window?.backingScaleFactor ?? 1) * 100
        zoomButton.title = hasImage ? String(format: "%.0f%%", percent) : "Fit"
        zoomButton.setAccessibilityValue(zoomButton.title)
        if let decoded {
            var parts = ["\(Int(decoded.pixelSize.width)) × \(Int(decoded.pixelSize.height))", decoded.typeName,
                         ByteCountFormatter.string(fromByteCount: Int64(decoded.fileSize), countStyle: .file)]
            if decoded.frameCount > 1 { parts.append(animationPaused ? "Paused" : "Animated") }
            if decoded.isDownsampled { parts.append("Reduced preview") }
            if slideshow != nil { parts.append("Slideshow · 5s") }
            if folderWarning != nil { parts.append("Folder unavailable") }
            status.stringValue = parts.joined(separator: "  ·  ")
        } else { status.stringValue = folderWarning ?? "Scroll to zoom  ·  ← → to browse  ·  Drag to pan" }
        status.toolTip = folderWarning ?? catalog.current?.path
        position.stringValue = catalog.urls.isEmpty ? "" : "\(catalog.index + 1) / \(catalog.urls.count)"
        buttons["play"]?.image = NSImage(systemSymbolName: slideshow == nil ? "play" : "pause", accessibilityDescription: "Slideshow")
    }
    func navigate(_ delta: Int) {
        guard !catalog.urls.isEmpty else { return }
        if delta == Int.min { catalog.select(0) }
        else if delta == Int.max { catalog.select(catalog.urls.count - 1) }
        else { catalog.move(delta) }
        loadCurrent()
    }
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open an image or folder"; panel.canChooseDirectories = true
        panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.beginSheetModal(for: window!) { [weak self] response in
            if response == .OK, let url = panel.url { self?.open(url) }
        }
    }
    @objc func previous(_ sender: Any?) { navigate(-1) }
    @objc func next(_ sender: Any?) { navigate(1) }
    @objc func zoomIn(_ sender: Any?) { canvas.zoom(1.25) }
    @objc func zoomOut(_ sender: Any?) { canvas.zoom(0.8) }
    @objc func fit(_ sender: Any?) { canvas.fit() }
    @objc func actualSize(_ sender: Any?) { canvas.actualSize() }
    @objc func rotate(_ sender: Any?) { canvas.rotate() }
    @objc func toggleFullScreen(_ sender: Any?) { window?.toggleFullScreen(sender) }
    @objc func reveal(_ sender: Any?) { if let url = catalog.current { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc func copy(_ sender: Any?) {
        guard let url = catalog.current else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([url as NSURL])
    }
    @objc func togglePlayback(_ sender: Any?) {
        guard let decoded, decoded.frameCount > 1 else { toggleSlideshow(sender); return }
        animationPaused.toggle(); animationID = UUID(); animationTimer?.invalidate(); animationTimer = nil
        if !animationPaused { animateNext() }; updateStatus()
    }
    @objc func toggleSlideshow(_ sender: Any?) {
        if slideshow != nil { stopSlideshow(); return }
        guard catalog.urls.count > 1 else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.navigate(1) }
        slideshow = timer; RunLoop.main.add(timer, forMode: .common); updateStatus()
    }
    private func stopSlideshow() { slideshow?.invalidate(); slideshow = nil; updateStatus() }
    @objc func showInfo(_ sender: Any?) {
        guard let decoded, let url = catalog.current else { return }
        let alert = NSAlert(); alert.messageText = url.lastPathComponent
        alert.informativeText = "\(Int(decoded.pixelSize.width)) × \(Int(decoded.pixelSize.height)) pixels\n\(decoded.typeName) · \(ByteCountFormatter.string(fromByteCount: Int64(decoded.fileSize), countStyle: .file))\n\(decoded.frameCount) frame(s)\n\n\(url.path)" + (decoded.isDownsampled ? "\n\nThis very large image uses a reduced preview to limit memory use." : "")
        alert.addButton(withTitle: "Done"); alert.addButton(withTitle: "Show in Finder")
        alert.beginSheetModal(for: window!) { [weak self] response in if response == .alertSecondButtonReturn { self?.reveal(nil) } }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(previous(_:)), #selector(next(_:)), #selector(toggleSlideshow(_:)): return catalog.urls.count > 1
        case #selector(reveal(_:)), #selector(copy(_:)): return catalog.current != nil
        case #selector(togglePlayback(_:)): return (decoded?.frameCount ?? 0) > 1 || catalog.urls.count > 1
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(fit(_:)), #selector(actualSize(_:)), #selector(rotate(_:)), #selector(showInfo(_:)): return decoded != nil
        default: return true
        }
    }
    func windowWillClose(_ notification: Notification) {
        isClosed = true; cancelDecoding(); stopSlideshow(); folderMonitor = nil; fileMonitor = nil
        refreshWork?.cancel(); reloadWork?.cancel(); decoded = nil; canvas.image = nil
    }
    func windowDidMiniaturize(_ notification: Notification) { animationID = UUID(); animationTimer?.invalidate(); animationTimer = nil; stopSlideshow() }
    func windowDidDeminiaturize(_ notification: Notification) { animateNext() }
    func windowDidChangeBackingProperties(_ notification: Notification) {
        canvas.viewport.nativeScale = 1 / (window?.backingScaleFactor ?? 1)
        if canvas.viewport.fitsWindow { canvas.fit() }
        updateStatus()
    }
}
