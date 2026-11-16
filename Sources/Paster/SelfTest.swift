import AppKit
import SwiftUI

/// Headless checks (`Paster --self-test`). Uses a throwaway store, never the real history.
enum SelfTest {
    private static var failures = 0

    private static func check(_ cond: Bool, _ name: String) {
        print((cond ? "PASS  " : "FAIL  ") + name)
        if !cond { failures += 1 }
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
}
