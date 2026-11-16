import AppKit
import SwiftUI

/// Headless checks (`Paster --self-test`) and a UI snapshot (`Paster --snapshot out.png`).
/// Both refuse to touch the real history unless PASTER_DATA_DIR points somewhere else.
enum SelfTest {
    private static var failures = 0

    private static func check(_ cond: Bool, _ name: String) {
        print((cond ? "PASS  " : "FAIL  ") + name)
        if !cond { failures += 1 }
    }

    private static var usesScratchStore: Bool {
        !(ProcessInfo.processInfo.environment["PASTER_DATA_DIR"] ?? "").isEmpty
    }

    static func run() -> Int32 {
        // Parsers
        check(ColorParser.parse("#ff0000") != nil, "hex colour")
        check(ColorParser.parse("#abc") != nil, "short hex colour")
        check(ColorParser.parse("rgb(10, 20, 30)") != nil, "rgb() colour")
        check(ColorParser.parse("#xyz") == nil, "invalid hex rejected")
        check(ClipboardMonitor.isLink("https://example.com/a?b=1"), "https link")
        check(!ClipboardMonitor.isLink("hello world"), "plain text is not a link")
        check(!ClipboardMonitor.isLink("https://"), "link without host rejected")

        // Classification
        func classify(_ s: String) -> ClipKind? { ClipboardMonitor.process(RawCapture(string: s))?.0.kind }
        check(classify("hello") == .text, "classify text")
        check(classify("https://apple.com") == .link, "classify link")
        check(classify("#336699") == .color, "classify colour")
        check(classify("   \n ") == nil, "whitespace ignored")
        var rich = RawCapture(string: "bold")
        rich.rtf = Data("{\\rtf1 {\\b bold}}".utf8)
        check(ClipboardMonitor.process(rich)?.0.kind == .richText, "classify rich text")
        var files = RawCapture()
        files.fileURLs = [URL(fileURLWithPath: "/tmp/a.txt")]
        check(ClipboardMonitor.process(files)?.0.kind == .file, "classify file")
        var img = RawCapture()
        img.png = samplePNG()
        let imgResult = ClipboardMonitor.process(img)
        check(imgResult?.0.kind == .image && imgResult?.1["png"] != nil && imgResult?.1["thumb.png"] != nil, "classify image + thumbnail")

        // Store (scratch directory only)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paster-selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir)
        let (a, _) = ClipboardMonitor.process(RawCapture(string: "one"))!
        let (b, _) = ClipboardMonitor.process(RawCapture(string: "two"))!
        let (a2, _) = ClipboardMonitor.process(RawCapture(string: "one"))!
        store.insertCaptured(a, blobs: [:])
        store.insertCaptured(b, blobs: [:])
        store.insertCaptured(a2, blobs: [:])
        check(store.historyItems.count == 2, "dedupe identical copies")
        check(store.historyItems.first?.text == "one", "re-copied item moves to top")
        let board = store.addPinboard(name: "Work")
        store.pin(store.historyItems[1], to: board.id)
        store.pin(store.historyItems[1], to: board.id)
        check(store.count(in: board.id) == 1, "pin once per board")
        store.clearHistory()
        check(store.historyItems.isEmpty && store.count(in: board.id) == 1, "clear history keeps pinboards")
        store.saveNow(synchronously: true)
        let reloaded = Store(directory: dir)
        check(reloaded.pinboards.count == 1 && reloaded.count(in: board.id) == 1, "persistence round-trip")

        print(failures == 0 ? "All self-tests passed." : "\(failures) self-test(s) failed.")
        return failures == 0 ? 0 : 1
    }

    static func samplePNG(width: Int = 64, height: Int = 48) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let g = NSGradient(starting: .systemTeal, ending: .systemIndigo)!
        g.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 35)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    /// Renders the strip with sample data to a PNG, for checking the layout without
    /// showing anything on screen.
    static func snapshot(to path: String) -> Int32 {
        guard usesScratchStore else {
            print("Refusing to snapshot: set PASTER_DATA_DIR to a scratch directory.")
            return 2
        }
        let store = Store.shared
        if store.items.isEmpty {
            func add(_ raw: RawCapture) {
                if let (item, blobs) = ClipboardMonitor.process(raw) { store.insertCaptured(item, blobs: blobs) }
            }
            var r = RawCapture(string: "#4F7CFF"); r.bundleID = "com.apple.Safari"; r.appName = "Safari"; add(r)
            r = RawCapture(); r.png = samplePNG(width: 640, height: 400); r.bundleID = "com.apple.Preview"; r.appName = "Preview"; add(r)
            r = RawCapture(); r.fileURLs = [URL(fileURLWithPath: "/Applications/Safari.app")]; r.bundleID = "com.apple.finder"; add(r)
            r = RawCapture(string: "https://developer.apple.com/documentation/appkit/nspasteboard"); r.bundleID = "com.apple.Safari"; add(r)
            r = RawCapture(string: "func greet(_ name: String) -> String {\n    \"Hello, \\(name)!\"\n}"); r.bundleID = "com.apple.dt.Xcode"; add(r)
            r = RawCapture(string: "明天下午三點開會，記得帶上季度報告和簡報檔案。"); r.bundleID = "com.apple.Notes"; add(r)
            _ = store.addPinboard(name: "Work")
            _ = store.addPinboard(name: "Snippets")
        }
        let model = PanelModel()
        let size = NSSize(width: 1440, height: PanelController.panelHeight)
        let root = PanelView(model: model)
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.16))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return 1 }
        do { try png.write(to: URL(fileURLWithPath: path)) } catch { print(error); return 1 }
        print("Snapshot written to \(path)")
        return 0
    }
}
