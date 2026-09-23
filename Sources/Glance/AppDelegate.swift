import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var viewer: ViewerWindowController?
    private func currentViewer() -> ViewerWindowController {
        if let viewer, viewer.window?.isVisible == true { return viewer }
        let controller = ViewerWindowController(); viewer = controller
        return controller
    }
    func applicationWillFinishLaunching(_ notification: Notification) { buildMenu() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if viewer == nil {
            let controller = currentViewer(); controller.showWindow(nil)
            controller.window?.makeFirstResponder(controller.canvas)
        }
        NSApp.activate(ignoringOtherApps: true)
        let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if let path = paths.first { currentViewer().open(URL(fileURLWithPath: path)) }
    }
    func application(_ sender: NSApplication, open urls: [URL]) {
        if let url = urls.first { currentViewer().open(url) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { let controller = currentViewer(); controller.showWindow(nil); controller.window?.makeFirstResponder(controller.canvas) }
        return true
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    @objc func openDocument(_ sender: Any?) { let controller = currentViewer(); controller.showWindow(nil); controller.openDocument(sender) }
    @objc private func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { currentViewer().open(url) }
    }
    @objc private func clearRecent(_ sender: Any?) { NSDocumentController.shared.clearRecentDocuments(sender) }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = url; item.toolTip = url.path; menu.addItem(item)
        }
        if menu.items.isEmpty { let item = NSMenuItem(title: "No Recent Images", action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self; menu.addItem(clear)
    }
    @objc func help(_ sender: Any?) {
        let alert = NSAlert(); alert.messageText = "Glance shortcuts"
        alert.informativeText = "← / →     Previous / next image (loops)\nScroll or pinch     Zoom around the pointer\nDrag     Pan a zoomed image\nOption + scroll     Pan\n0 / ⌘0     Fit to window\n1 / ⌘1     Actual pixels\n+ / −     Zoom in / out\nDouble-click     Fit / actual pixels\n⌘R     Rotate view clockwise\nSpace     Pause animation / toggle slideshow\n⇧⌘P     Toggle slideshow (5 seconds)\n⌃⌘F     Toggle full screen\nEscape     Stop slideshow / leave full screen\n⌘I     Image information\n⇧⌘R     Show in Finder\n⌘O     Open an image or folder\n\nImages are never modified. TIFF, PDF, PSD, and image collections show the first page or composite. Camera RAW support depends on macOS."
        alert.runModal()
    }
    private func buildMenu() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); main.addItem(item)
            let menu = NSMenu(title: title); item.submenu = menu; return menu
        }
        @discardableResult func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers; item.target = target; menu.addItem(item); return item
        }
        let app = menu("Glance")
        add(app, "About Glance", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        let services = NSMenu(title: "Services"), serviceItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        serviceItem.submenu = services; app.addItem(serviceItem); NSApp.servicesMenu = services
        app.addItem(.separator())
        add(app, "Hide Glance", #selector(NSApplication.hide(_:)), "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator()); add(app, "Quit Glance", #selector(NSApplication.terminate(_:)), "q")
        let file = menu("File")
        add(file, "Open…", #selector(openDocument(_:)), "o", target: self)
        let recent = NSMenu(title: "Open Recent"); recent.delegate = self
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent; file.addItem(recentItem)
        file.addItem(.separator())
        add(file, "Show in Finder", #selector(ViewerWindowController.reveal(_:)), "r", [.command, .shift])
        add(file, "Image Information", #selector(ViewerWindowController.showInfo(_:)), "i")
        file.addItem(.separator()); add(file, "Close Window", #selector(NSWindow.performClose(_:)), "w")
        let edit = menu("Edit"); add(edit, "Copy Image File", #selector(ViewerWindowController.copy(_:)), "c")
        let view = menu("View")
        add(view, "Zoom In", #selector(ViewerWindowController.zoomIn(_:)), "+")
        add(view, "Zoom Out", #selector(ViewerWindowController.zoomOut(_:)), "-")
        add(view, "Fit to Window", #selector(ViewerWindowController.fit(_:)), "0")
        add(view, "Actual Pixels", #selector(ViewerWindowController.actualSize(_:)), "1")
        view.addItem(.separator()); add(view, "Rotate Clockwise", #selector(ViewerWindowController.rotate(_:)), "r")
        view.addItem(.separator()); add(view, "Enter Full Screen", #selector(ViewerWindowController.toggleFullScreen(_:)), "f", [.command, .control])
        let go = menu("Go")
        add(go, "Previous Image", #selector(ViewerWindowController.previous(_:)), String(UnicodeScalar(NSLeftArrowFunctionKey)!), [])
        add(go, "Next Image", #selector(ViewerWindowController.next(_:)), String(UnicodeScalar(NSRightArrowFunctionKey)!), [])
        go.addItem(.separator()); add(go, "Play / Pause", #selector(ViewerWindowController.togglePlayback(_:)), " ", [])
        add(go, "Start / Stop Slideshow", #selector(ViewerWindowController.toggleSlideshow(_:)), "p", [.command, .shift])
        let window = menu("Window"); NSApp.windowsMenu = window
        add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        let helpMenu = menu("Help"); NSApp.helpMenu = helpMenu
        add(helpMenu, "Glance Help", #selector(help(_:)), "?", target: self)
        NSApp.mainMenu = main
    }
}
