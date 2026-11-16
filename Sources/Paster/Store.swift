import AppKit
import CryptoKit

/// Persistent history: a JSON index plus blob files (images, RTF, HTML) in Application Support.
final class Store: ObservableObject {
    static let shared: Store = {
        if let custom = ProcessInfo.processInfo.environment["PASTER_DATA_DIR"], !custom.isEmpty {
            return Store(directory: URL(fileURLWithPath: custom))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Store(directory: base.appendingPathComponent("Paster", isDirectory: true))
    }()

    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var pinboards: [Pinboard] = []

    let baseDir: URL
    let blobsDir: URL
    private let dbURL: URL
    private let ioQueue = DispatchQueue(label: "paster.store.io", qos: .utility)
    private var saveScheduled = false

    private struct Database: Codable {
        var version = 1
        var items: [ClipItem]
        var pinboards: [Pinboard]
    }

    static let blobExtensions = ["png", "thumb.png", "rtf", "html"]

    init(directory: URL) {
        baseDir = directory
        blobsDir = directory.appendingPathComponent("blobs", isDirectory: true)
        dbURL = directory.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: dbURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let db = try? decoder.decode(Database.self, from: data) {
            items = db.items
            pinboards = db.pinboards
        } else {
            // Keep the unreadable file around instead of silently overwriting it.
            let backup = baseDir.appendingPathComponent("history.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: dbURL, to: backup)
        }
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.saveNow()
        }
    }

    func saveNow(synchronously: Bool = false) {
        saveScheduled = false
        let db = Database(items: items, pinboards: pinboards)
        let url = dbURL
        let work = {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            if let data = try? encoder.encode(db) {
                try? data.write(to: url, options: .atomic)
            }
        }
        if synchronously { ioQueue.sync(execute: work) } else { ioQueue.async(execute: work) }
    }

    // MARK: Blobs

    func blobURL(_ id: UUID, _ ext: String) -> URL {
        blobsDir.appendingPathComponent("\(id.uuidString).\(ext)")
    }

    func blobData(_ id: UUID, _ ext: String) -> Data? {
        try? Data(contentsOf: blobURL(id, ext))
    }

    private func removeBlobs(for ids: [UUID]) {
        let urls = ids.flatMap { id in Store.blobExtensions.map { blobURL(id, $0) } }
        ioQueue.async {
            for u in urls { try? FileManager.default.removeItem(at: u) }
        }
    }

    // MARK: History

    var historyItems: [ClipItem] { items.filter { $0.pinboardID == nil } }

    /// Insert a freshly captured item at the top of the history. If identical content is
    /// already in the history, that entry is moved to the top instead (dedupe).
    func insertCaptured(_ item: ClipItem, blobs: [String: Data]) {
        if let idx = items.firstIndex(where: { $0.pinboardID == nil && $0.contentHash == item.contentHash }) {
            var existing = items.remove(at: idx)
            existing.date = item.date
            existing.sourceBundleID = item.sourceBundleID ?? existing.sourceBundleID
            existing.sourceAppName = item.sourceAppName ?? existing.sourceAppName
            items.insert(existing, at: 0)
        } else {
            for (ext, data) in blobs {
                try? data.write(to: blobURL(item.id, ext), options: .atomic)
            }
            items.insert(item, at: 0)
            trim(save: false)
        }
        scheduleSave()
    }

    func trim(save: Bool = true) {
        let limit = Settings.shared.historyLimit
        guard limit > 0 else { return }
        var seen = 0
        var removed: [UUID] = []
        let kept = items.filter { item in
            guard item.pinboardID == nil else { return true }
            seen += 1
            if seen > limit { removed.append(item.id); return false }
            return true
        }
        guard !removed.isEmpty else { return }
        items = kept
        removeBlobs(for: removed)
        if save { scheduleSave() }
    }

    func delete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: idx)
        removeBlobs(for: [id])
        scheduleSave()
    }

    /// Removes every history item. Pinboard items are kept.
    func clearHistory() {
        let removed = items.filter { $0.pinboardID == nil }.map(\.id)
        items.removeAll { $0.pinboardID == nil }
        removeBlobs(for: removed)
        scheduleSave()
    }

    // MARK: Pinboards

    @discardableResult
    func addPinboard(name: String) -> Pinboard {
        let used = Set(pinboards.map(\.colorIndex))
        let color = (0..<8).first { !used.contains($0) } ?? pinboards.count % 8
        let board = Pinboard(name: name, colorIndex: color)
        pinboards.append(board)
        scheduleSave()
        return board
    }

    func renamePinboard(_ id: UUID, to name: String) {
        guard let idx = pinboards.firstIndex(where: { $0.id == id }) else { return }
        pinboards[idx].name = name
        scheduleSave()
    }

    func deletePinboard(_ id: UUID) {
        let removed = items.filter { $0.pinboardID == id }.map(\.id)
        items.removeAll { $0.pinboardID == id }
        pinboards.removeAll { $0.id == id }
        removeBlobs(for: removed)
        scheduleSave()
    }

    /// Pinning stores an independent copy of the item in the pinboard, so it survives
    /// history trimming and "Clear History".
    func pin(_ item: ClipItem, to boardID: UUID) {
        if items.contains(where: { $0.pinboardID == boardID && $0.contentHash == item.contentHash }) { return }
        var copy = item
        copy.id = UUID()
        copy.pinboardID = boardID
        let fm = FileManager.default
        for ext in Store.blobExtensions {
            let src = blobURL(item.id, ext)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: blobURL(copy.id, ext))
            }
        }
        let insertAt = items.firstIndex(where: { $0.pinboardID == boardID }) ?? items.count
        items.insert(copy, at: insertAt)
        scheduleSave()
    }

    func count(in boardID: UUID?) -> Int {
        items.reduce(0) { $0 + ($1.pinboardID == boardID ? 1 : 0) }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// In-memory caches for card thumbnails and application / file icons.
final class ImageCache {
    static let shared = ImageCache()
    private let thumbs = NSCache<NSString, NSImage>()
    private let icons = NSCache<NSString, NSImage>()
    fileprivate var appColors: [String: NSColor] = [:]

    init() {
        thumbs.countLimit = 300
        icons.countLimit = 300
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let img = thumbs.object(forKey: key) { return img }
        let store = Store.shared
        guard let img = NSImage(contentsOf: store.blobURL(item.id, "thumb.png"))
                ?? NSImage(contentsOf: store.blobURL(item.id, "png")) else { return nil }
        thumbs.setObject(img, forKey: key)
        return img
    }

    func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        let key = "app:\(bundleID)" as NSString
        if let img = icons.object(forKey: key) { return img }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(img, forKey: key)
        return img
    }

    func fileIcon(path: String) -> NSImage {
        let key = "file:\(path)" as NSString
        if let img = icons.object(forKey: key) { return img }
        let img = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(img, forKey: key)
        return img
    }
}

extension ImageCache {
    /// A header colour derived from the source application's icon (saturation-weighted average),
    /// darkened enough that white header text stays readable.
    func appColor(bundleID: String?) -> NSColor? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let c = appColors[bundleID] { return c }
        guard let icon = appIcon(bundleID: bundleID),
              let color = ImageCache.dominantColor(of: icon) else { return nil }
        appColors[bundleID] = color
        return color
    }

    static func dominantColor(of image: NSImage) -> NSColor? {
        let n = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: n * 4, bitsPerPixel: 32),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        image.draw(in: NSRect(x: 0, y: 0, width: n, height: n), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let p = rep.bitmapData else { return nil }
        var sr = 0.0, sg = 0.0, sb = 0.0, sw = 0.0
        for i in stride(from: 0, to: n * n * 4, by: 4) {
            let a = Double(p[i + 3]) / 255
            guard a > 0.5 else { continue }
            let r = Double(p[i]) / 255 / a, g = Double(p[i + 1]) / 255 / a, b = Double(p[i + 2]) / 255 / a
            let sat = max(r, g, b) - min(r, g, b)
            let w = sat * sat + 0.02
            sr += r * w; sg += g * w; sb += b * w; sw += w
        }
        guard sw > 0 else { return nil }
        let base = NSColor(srgbRed: min(sr / sw, 1), green: min(sg / sw, 1), blue: min(sb / sw, 1), alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, al: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &v, alpha: &al)
        if s < 0.12 { return NSColor(srgbRed: 0.36, green: 0.39, blue: 0.45, alpha: 1) }
        return NSColor(hue: h, saturation: min(max(s, 0.55), 0.85), brightness: min(max(v, 0.55), 0.78), alpha: 1)
    }
}
