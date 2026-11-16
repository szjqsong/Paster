import AppKit
import SwiftUI

/// Renders README screenshots offscreen with sample data (`Paster --snapshot out.png --scene <name>`).
/// Scenes: strip, search, pinboard, preview, prefs-general, prefs-privacy.
/// Requires PASTER_DATA_DIR so the real clipboard history is never read or shown.
enum Screenshots {
    static let width: CGFloat = 1440

    static func render(scene: String, to path: String, light: Bool) -> Int32 {
        guard !(ProcessInfo.processInfo.environment["PASTER_DATA_DIR"] ?? "").isEmpty else {
            print("Refusing to render: set PASTER_DATA_DIR to a scratch directory.")
            return 2
        }
        PasteService.assumeTrusted = true
        seedSampleData()
        let scheme: ColorScheme = light ? .light : .dark
        let model = PanelModel()
        let store = Store.shared

        let view: AnyView
        let height: CGFloat
        var canvasWidth = width
        switch scene {
        case "strip", "search", "pinboard":
            if scene == "search" { model.query = "Safari" }
            if scene == "pinboard" { model.boardID = store.pinboards.first?.id }
            height = 200 + PanelController.panelHeight
            view = AnyView(desktop(stripOnly: true, model: model, scheme: scheme))
        case "preview":
            model.previewItem = store.historyItems.first
            height = 900
            view = AnyView(desktop(stripOnly: false, model: model, scheme: scheme))
        case "prefs-general", "prefs-privacy":
            height = 640
            canvasWidth = 900
            view = AnyView(ZStack {
                Backdrop()
                FakeWindow(title: L("Paster Preferences", "Paster 偏好設定"), scheme: scheme) {
                    PreferencesView(tab: scene == "prefs-general" ? 0 : 1)
                }
            })
        default:
            print("Unknown scene \(scene)")
            return 2
        }
        return write(view.frame(width: canvasWidth, height: height).environment(\.colorScheme, scheme),
                     size: NSSize(width: canvasWidth, height: height), to: path)
    }

    // MARK: Composition

    @ViewBuilder
    private static func desktop(stripOnly: Bool, model: PanelModel, scheme: ColorScheme) -> some View {
        ZStack(alignment: .bottom) {
            Backdrop()
            if let item = model.previewItem, !stripOnly {
                PreviewView(item: item)
                    .frame(width: 820, height: 420)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
            }
            PanelView(model: model)
                .frame(width: width, height: PanelController.panelHeight)
                // Stand-in for the live blur material, which does not render offscreen.
                .background(scheme == .dark ? Color(white: 0.11).opacity(0.86) : Color(white: 0.97).opacity(0.88))
                .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Color.white.opacity(0.18)), alignment: .top)
        }
    }

    /// Original abstract wallpaper so screenshots don't ship anyone else's artwork.
    struct Backdrop: View {
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.38),
                                        Color(red: 0.42, green: 0.20, blue: 0.55),
                                        Color(red: 0.95, green: 0.45, blue: 0.40)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color(red: 0.30, green: 0.55, blue: 0.95).opacity(0.55))
                    .frame(width: 700).blur(radius: 120).offset(x: -380, y: -160)
                Circle().fill(Color(red: 1.0, green: 0.70, blue: 0.35).opacity(0.45))
                    .frame(width: 600).blur(radius: 120).offset(x: 420, y: 120)
            }
        }
    }

    struct FakeWindow<Content: View>: View {
        let title: String
        let scheme: ColorScheme
        @ViewBuilder let content: () -> Content

        var body: some View {
            VStack(spacing: 0) {
                ZStack {
                    HStack(spacing: 8) {
                        Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12)
                        Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12)
                        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12)
                        Spacer()
                    }
                    Text(title).font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
                content()
            }
            .frame(width: 600)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 14)
        }
    }

    private static func write<V: View>(_ view: V, size: NSSize, to path: String) -> Int32 {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return 1 }
        do { try png.write(to: URL(fileURLWithPath: path)) } catch { print(error); return 1 }
        print("Wrote \(path)")
        return 0
    }

    // MARK: Sample data

    private static func seedSampleData() {
        let store = Store.shared
        guard store.items.isEmpty else { return }
        func add(_ raw: RawCapture) {
            if let (item, blobs) = ClipboardMonitor.process(raw) { store.insertCaptured(item, blobs: blobs) }
        }
        func text(_ s: String, _ bid: String, _ app: String) -> RawCapture {
            var r = RawCapture(string: s); r.bundleID = bid; r.appName = app; return r
        }
        // Inserted oldest first; the last one ends up at the left of the strip.
        add(text("hello@example.com", "com.apple.mail", "Mail"))
        add(text("#FF6B35", "com.apple.Safari", "Safari"))
        add(text("git commit -m \"Add pinboards\" && git push origin main", "com.apple.Terminal", "Terminal"))
        var file = RawCapture(); file.fileURLs = [URL(fileURLWithPath: "/Applications/Safari.app")]
        file.bundleID = "com.apple.finder"; file.appName = "Finder"; add(file)
        var img = RawCapture(); img.png = landscapePNG(); img.bundleID = "com.apple.Preview"; img.appName = "Preview"
        img.recognizeText = false; add(img)
        add(text("https://developer.apple.com/documentation/appkit/nspasteboard", "com.apple.Safari", "Safari"))
        add(text("func greet(_ name: String) -> String {\n    \"Hello, \\(name)!\"\n}", "com.apple.dt.Xcode", "Xcode"))
        add(text("週五下午三點產品評審會議\n\n• 帶上 Q4 產品路線圖\n• 確認 1.1 版發佈時間\n• 準備功能示範影片\n• 會後整理待辦事項並寄給大家",
                 "com.apple.Notes", "Notes"))

        let work = store.addPinboard(name: L("Work", "工作"))
        let phrases = store.addPinboard(name: L("Snippets", "常用片語"))
        for item in store.historyItems where [.link, .text].contains(item.kind) && item.sourceBundleID != "com.apple.Notes" {
            store.pin(item, to: work.id)
        }
        let reply = text("您好，感謝您的來信！我們已收到您的問題，會在一個工作天內回覆。", "com.apple.mail", "Mail")
        if let (item, blobs) = ClipboardMonitor.process(reply) {
            store.insertCaptured(item, blobs: blobs)
            store.pin(item, to: phrases.id)
            store.delete(item.id)
        }
        // Keep the Notes item first in history.
        if let notes = store.historyItems.first(where: { $0.sourceBundleID == "com.apple.Notes" }) {
            store.insertCaptured(notes, blobs: [:])
        }
        store.saveNow(synchronously: true)
    }

    /// Procedural landscape used as the sample image.
    static func landscapePNG(width: Int = 1280, height: Int = 800) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let w = CGFloat(width), h = CGFloat(height)
        NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.62, blue: 0.40, alpha: 1),
                            NSColor(srgbRed: 0.98, green: 0.80, blue: 0.55, alpha: 1),
                            NSColor(srgbRed: 0.55, green: 0.70, blue: 0.95, alpha: 1)])!
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
        NSColor(srgbRed: 1.0, green: 0.93, blue: 0.75, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: w * 0.62, y: h * 0.42, width: 170, height: 170)).fill()
        func ridge(_ base: CGFloat, _ amp: CGFloat, _ phase: CGFloat, _ color: NSColor) {
            let p = NSBezierPath()
            p.move(to: .zero)
            for x in stride(from: CGFloat(0), through: w, by: 8) {
                let y = base + amp * sin(x / w * 5 + phase) + amp * 0.4 * sin(x / w * 13 + phase * 2)
                p.line(to: NSPoint(x: x, y: y))
            }
            p.line(to: NSPoint(x: w, y: 0)); p.close()
            color.setFill(); p.fill()
        }
        ridge(h * 0.42, 60, 0.3, NSColor(srgbRed: 0.45, green: 0.38, blue: 0.62, alpha: 1))
        ridge(h * 0.30, 50, 1.7, NSColor(srgbRed: 0.30, green: 0.26, blue: 0.48, alpha: 1))
        ridge(h * 0.16, 40, 3.1, NSColor(srgbRed: 0.17, green: 0.15, blue: 0.32, alpha: 1))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}
