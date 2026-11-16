import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private(set) var panelController: PanelController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = PanelController()
        setUpStatusItem()

        ClipboardMonitor.shared.start()

        HotKeyManager.shared.onHotKey = { [weak self] in self?.panelController.toggle() }
        registerHotKey()
        NotificationCenter.default.addObserver(forName: .pasterHotKeyChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotKey()
        }
        Settings.shared.$paused
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusIcon() } }
            .store(in: &cancellables)

        if !Settings.shared.hasLaunchedBefore {
            Settings.shared.hasLaunchedBefore = true
            // Ask once for Accessibility so "paste directly" works out of the box.
            PasteService.requestAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.saveNow(synchronously: true)
    }

    /// Re-opening Paster from Finder / Launchpad shows the strip.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return false
    }

    private func registerHotKey() {
        let s = Settings.shared
        if !HotKeyManager.shared.register(keyCode: s.hotKeyCode, modifiers: s.hotKeyModifiers) {
            let alert = NSAlert()
            alert.messageText = L("Shortcut unavailable", "無法使用此快捷鍵")
            alert.informativeText = L("\(s.hotKeyDisplay) is already used by another app. Choose another one in Preferences.",
                                      "\(s.hotKeyDisplay) 已被其他 App 使用，請在偏好設定中改用其他快捷鍵。")
            alert.runModal()
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let name = Settings.shared.paused ? "pause.circle" : "list.clipboard"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Paster")
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paster")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared

        let open = NSMenuItem(title: L("Open Paster", "打開 Paster"), action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(withTitle: L("Shortcut: ", "快捷鍵：") + s.hotKeyDisplay, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        let recent = Store.shared.historyItems.prefix(10)
        if !recent.isEmpty {
            menu.addItem(withTitle: L("Recent", "最近項目"), action: nil, keyEquivalent: "").isEnabled = false
            for (i, item) in recent.enumerated() {
                let mi = NSMenuItem(title: item.menuTitle, action: #selector(copyRecent(_:)),
                                    keyEquivalent: i < 9 ? "\(i + 1)" : "")
                mi.target = self
                mi.representedObject = item.id
                if let icon = ImageCache.shared.appIcon(bundleID: item.sourceBundleID)?.copy() as? NSImage {
                    icon.size = NSSize(width: 16, height: 16)
                    mi.image = icon
                }
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }

        let pause = NSMenuItem(title: s.paused ? L("Resume Capturing", "繼續記錄") : L("Pause Capturing", "暫停記錄"),
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let prefs = NSMenuItem(title: L("Preferences…", "偏好設定⋯"), action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Quit Paster", "結束 Paster"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openPanel() {
        // Let the menu finish closing first so the previous app is still the frontmost one.
        DispatchQueue.main.async { self.panelController.show() }
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = Store.shared.items.first(where: { $0.id == id }) else { return }
        PasteService.write(item, plainText: Settings.shared.plainTextByDefault)
    }

    @objc private func togglePause() {
        Settings.shared.paused.toggle()
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.show()
    }
}
