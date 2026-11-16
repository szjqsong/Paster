import AppKit
import SwiftUI

enum ClipKind: String, Codable, CaseIterable {
    case text, richText, link, image, file, color

    var label: String {
        switch self {
        case .text: return L("Text", "文字")
        case .richText: return L("Rich Text", "格式文字")
        case .link: return L("Link", "連結")
        case .image: return L("Image", "圖片")
        case .file: return L("File", "檔案")
        case .color: return L("Color", "顏色")
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        }
    }

    var tint: Color {
        switch self {
        case .text: return Color(red: 0.24, green: 0.48, blue: 0.96)
        case .richText: return Color(red: 0.45, green: 0.36, blue: 0.93)
        case .link: return Color(red: 0.07, green: 0.66, blue: 0.68)
        case .image: return Color(red: 0.93, green: 0.36, blue: 0.48)
        case .file: return Color(red: 0.95, green: 0.58, blue: 0.16)
        case .color: return Color(red: 0.40, green: 0.44, blue: 0.52)
        }
    }
}

enum TypeFilter: String, CaseIterable, Identifiable {
    case all, text, link, image, file, color
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return L("All", "全部")
        case .text: return L("Text", "文字")
        case .link: return L("Links", "連結")
        case .image: return L("Images", "圖片")
        case .file: return L("Files", "檔案")
        case .color: return L("Colors", "顏色")
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        }
    }

    func matches(_ kind: ClipKind) -> Bool {
        switch self {
        case .all: return true
        case .text: return kind == .text || kind == .richText
        case .link: return kind == .link
        case .image: return kind == .image
        case .file: return kind == .file
        case .color: return kind == .color
        }
    }
}

struct ClipItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ClipKind
    /// Plain text, URL string, colour string, or joined file names (for search).
    var text: String = ""
    var filePaths: [String] = []
    var hasRTF = false
    var hasHTML = false
    var pixelWidth = 0
    var pixelHeight = 0
    var byteSize = 0
    var date = Date()
    var sourceBundleID: String?
    var sourceAppName: String?
    var contentHash = ""
    /// nil = clipboard history; otherwise the pinboard this copy lives in.
    var pinboardID: UUID?

    var detail: String {
        switch kind {
        case .text, .richText:
            let n = text.count
            return L("\(n) characters", "\(n) 個字元")
        case .link:
            return URL(string: text)?.host ?? text
        case .image:
            return "\(pixelWidth) × \(pixelHeight)"
        case .file:
            if filePaths.count == 1 {
                return (filePaths[0] as NSString).deletingLastPathComponent
            }
            return L("\(filePaths.count) files", "\(filePaths.count) 個檔案")
        case .color:
            return text
        }
    }

    var menuTitle: String {
        let raw: String
        switch kind {
        case .image: raw = L("Image", "圖片") + " \(pixelWidth)×\(pixelHeight)"
        case .file: raw = filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        default: raw = text
        }
        let oneLine = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return oneLine.count > 48 ? String(oneLine.prefix(48)) + "…" : oneLine
    }

    func matches(query q: String) -> Bool {
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if text.range(of: q, options: opts) != nil { return true }
        if let app = sourceAppName, app.range(of: q, options: opts) != nil { return true }
        if kind == .file {
            for p in filePaths where p.range(of: q, options: opts) != nil { return true }
        }
        if kind.label.range(of: q, options: opts) != nil { return true }
        return false
    }
}

struct Pinboard: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var colorIndex: Int

    static let palette: [Color] = [
        Color(red: 0.96, green: 0.33, blue: 0.35),
        Color(red: 0.97, green: 0.60, blue: 0.15),
        Color(red: 0.94, green: 0.80, blue: 0.20),
        Color(red: 0.30, green: 0.76, blue: 0.42),
        Color(red: 0.16, green: 0.70, blue: 0.78),
        Color(red: 0.26, green: 0.50, blue: 0.96),
        Color(red: 0.58, green: 0.40, blue: 0.94),
        Color(red: 0.92, green: 0.40, blue: 0.72),
    ]

    var color: Color { Pinboard.palette[((colorIndex % 8) + 8) % 8] }
}

enum ColorParser {
    private static let rgbRegex = try! NSRegularExpression(
        pattern: #"^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*([0-9]*\.?[0-9]+)\s*)?\)$"#,
        options: [.caseInsensitive])

    static func parse(_ raw: String) -> NSColor? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count <= 40 else { return nil }
        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            guard [3, 4, 6, 8].contains(hex.count),
                  hex.allSatisfy({ $0.isHexDigit }) else { return nil }
            var full = hex
            if hex.count <= 4 { full = hex.map { "\($0)\($0)" }.joined() }
            guard let v = UInt64(full, radix: 16) else { return nil }
            let r, g, b, a: CGFloat
            if full.count == 8 {
                r = CGFloat((v >> 24) & 0xFF) / 255; g = CGFloat((v >> 16) & 0xFF) / 255
                b = CGFloat((v >> 8) & 0xFF) / 255; a = CGFloat(v & 0xFF) / 255
            } else {
                r = CGFloat((v >> 16) & 0xFF) / 255; g = CGFloat((v >> 8) & 0xFF) / 255
                b = CGFloat(v & 0xFF) / 255; a = 1
            }
            return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        }
        let ns = s as NSString
        if let m = rgbRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            func comp(_ i: Int) -> Double? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : Double(ns.substring(with: r))
            }
            guard let r = comp(1), let g = comp(2), let b = comp(3),
                  r <= 255, g <= 255, b <= 255 else { return nil }
            let a = min(comp(4) ?? 1, 1)
            return NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
        }
        return nil
    }
}
