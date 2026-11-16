import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PasteService {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "grant Accessibility access" dialog if Paster is not yet trusted.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Puts the item back on the general pasteboard.
    static func write(_ item: ClipItem, plainText: Bool) {
        let pb = NSPasteboard.general
        let store = Store.shared
        pb.clearContents()
        switch item.kind {
        case .text, .link, .color:
            pb.setString(item.text, forType: .string)
        case .richText:
            var types: [NSPasteboard.PasteboardType] = []
            let rtf = plainText ? nil : store.blobData(item.id, "rtf")
            let html = plainText ? nil : store.blobData(item.id, "html")
            if rtf != nil { types.append(.rtf) }
            if html != nil { types.append(.html) }
            types.append(.string)
            pb.declareTypes(types, owner: nil)
            if let rtf { pb.setData(rtf, forType: .rtf) }
            if let html { pb.setData(html, forType: .html) }
            pb.setString(item.text, forType: .string)
        case .image:
            if let png = store.blobData(item.id, "png") {
                var types: [NSPasteboard.PasteboardType] = [.png]
                let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation
                if tiff != nil { types.append(.tiff) }
                pb.declareTypes(types, owner: nil)
                pb.setData(png, forType: .png)
                if let tiff { pb.setData(tiff, forType: .tiff) }
            }
        case .file:
            if plainText {
                pb.setString(item.filePaths.joined(separator: "\n"), forType: .string)
            } else {
                let urls = item.filePaths
                    .filter { FileManager.default.fileExists(atPath: $0) }
                    .map { URL(fileURLWithPath: $0) as NSURL }
                if urls.isEmpty {
                    pb.setString(item.filePaths.joined(separator: "\n"), forType: .string)
                } else {
                    pb.writeObjects(urls)
                }
            }
        }
        ClipboardMonitor.shared.skipCurrentChange()
    }

    /// Simulates ⌘V in the target (previously frontmost) application.
    static func sendPaste(to target: NSRunningApplication?) {
        guard isTrusted else {
            requestAccessibility()
            return
        }
        var delay = 0.06
        if let target, !target.isTerminated, !target.isActive,
           target.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            target.activate()
            delay = 0.18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let key = CGKeyCode(kVK_ANSI_V)
            let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
            // Explicit flags so that a still-held Shift (⇧↩) does not turn this into ⇧⌘V.
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cgAnnotatedSessionEventTap)
            up?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
