import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PreferencesWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = L("Paster Preferences", "Paster 偏好設定")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreferencesView())
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        // Preferences is a normal window: temporarily become a regular app so it gets focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPane().tabItem { Label(L("General", "一般"), systemImage: "gearshape") }
            PrivacyPane().tabItem { Label(L("Privacy", "隱私"), systemImage: "hand.raised") }
            AboutPane().tabItem { Label(L("About", "關於"), systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 560, height: 470)
    }
}

// MARK: - General

struct GeneralPane: View {
    @ObservedObject var settings = Settings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = PasteService.isTrusted
    @State private var confirmClear = false

    static let limits = [100, 200, 500, 1000, 5000, 10000, 0]

    var body: some View {
        Form {
            LabeledContent(L("Open Paster:", "打開 Paster：")) {
                HotKeyRecorder()
            }
            Toggle(L("Launch Paster at login", "登入時啟動 Paster"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        NSSound.beep()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Divider().padding(.vertical, 4)

            Toggle(L("Paste items directly into the active app", "直接貼到目前使用中的 App"), isOn: $settings.pasteDirectly)
            Toggle(L("Always paste as plain text (⇧↩ does the opposite)", "一律以純文字貼上（⇧↩ 反向）"),
                   isOn: $settings.plainTextByDefault)
            HStack(spacing: 8) {
                Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(trusted ? .green : .orange)
                Text(trusted ? L("Accessibility access granted", "已授予「輔助使用」權限")
                             : L("Accessibility access is needed to paste directly", "直接貼上需要「輔助使用」權限"))
                if !trusted {
                    Button(L("Open Settings", "打開設定")) {
                        PasteService.requestAccessibility()
                        PasteService.openAccessibilitySettings()
                    }
                }
            }
            .font(.callout)

            Divider().padding(.vertical, 4)

            Picker(L("Keep history:", "保留歷史："), selection: $settings.historyLimit) {
                ForEach(GeneralPane.limits, id: \.self) { n in
                    Text(n == 0 ? L("Unlimited", "無限制") : L("\(n) items", "\(n) 個項目")).tag(n)
                }
            }
            .frame(maxWidth: 300)
            Button(L("Clear Clipboard History…", "清除剪貼簿歷史⋯")) { confirmClear = true }
                .confirmationDialog(L("Clear all clipboard history? Pinboards are kept.",
                                      "要清除所有剪貼簿歷史嗎？釘選板會保留。"),
                                    isPresented: $confirmClear) {
                    Button(L("Clear", "清除"), role: .destructive) { Store.shared.clearHistory() }
                }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = PasteService.isTrusted
        }
    }
}

/// Click, then press the new shortcut. Esc cancels, ⌫ resets to ⇧⌘V.
struct HotKeyRecorder: View {
    @ObservedObject var settings = Settings.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? L("Press shortcut…", "請按下快捷鍵⋯") : settings.hotKeyDisplay)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(minWidth: 120)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53 { stop(); return nil }
            if event.keyCode == 51 && flags.isEmpty {
                settings.hotKeyCode = 9
                settings.hotKeyModifiers = KeyNames.carbonModifiers(from: [.command, .shift])
                stop(); return nil
            }
            guard !flags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return nil }
            settings.hotKeyCode = UInt32(event.keyCode)
            settings.hotKeyModifiers = KeyNames.carbonModifiers(from: flags)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            NotificationCenter.default.post(name: .pasterHotKeyChanged, object: nil)
        }
    }
}

// MARK: - Privacy

struct PrivacyPane: View {
    @ObservedObject var settings = Settings.shared
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L("Pause clipboard capture", "暫停記錄剪貼簿"), isOn: $settings.paused)
            Toggle(L("Ignore confidential and transient content (password managers)",
                     "忽略機密與暫時性內容（密碼管理器）"), isOn: $settings.ignoreConcealed)
            Toggle(L("Hide Paster from screen sharing and recordings", "螢幕分享與錄影時隱藏 Paster"),
                   isOn: $settings.hideFromScreenSharing)
            Toggle(L("Recognize text in images (on-device) for search", "辨識圖片中的文字以便搜尋（裝置上處理）"),
                   isOn: $settings.recognizeTextInImages)

            Text(L("Ignore copies from these applications:", "不記錄以下 App 的拷貝內容："))
                .font(.headline).padding(.top, 6)
            List(selection: $selection) {
                ForEach(settings.excludedBundleIDs, id: \.self) { bid in
                    HStack(spacing: 8) {
                        if let icon = ImageCache.shared.appIcon(bundleID: bid) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "app.dashed").frame(width: 18, height: 18)
                        }
                        Text(appName(bid))
                        Spacer()
                        Text(bid).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(bid)
                }
            }
            .frame(minHeight: 150)
            HStack(spacing: 4) {
                Button { addApp() } label: { Image(systemName: "plus") }
                Button {
                    if let s = selection { settings.excludedBundleIDs.removeAll { $0 == s }; selection = nil }
                } label: { Image(systemName: "minus") }
                .disabled(selection == nil)
                Spacer()
                Button(L("Restore Defaults", "恢復預設")) {
                    settings.excludedBundleIDs = Settings.defaultExcludedBundleIDs
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func appName(_ bid: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bid
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bid = Bundle(url: url)?.bundleIdentifier, !settings.excludedBundleIDs.contains(bid) {
                settings.excludedBundleIDs.append(bid)
            }
        }
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Paster").font(.system(size: 22, weight: .bold))
            Text(L("Version", "版本") + " " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"))
                .foregroundStyle(.secondary)
            Text(L("A clipboard manager for macOS. History and pinboards are stored locally in ~/Library/Application Support/Paster.",
                   "macOS 剪貼簿管理工具。歷史與釘選板僅儲存在本機的 ~/Library/Application Support/Paster。"))
                .multilineTextAlignment(.center).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
