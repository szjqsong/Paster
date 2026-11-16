import SwiftUI
import AppKit

/// Large floating Quick Look–style preview shown above the strip (Space).
struct PreviewView: View {
    let item: ClipItem

    private var headerColor: Color {
        if let c = ImageCache.shared.appColor(bundleID: item.sourceBundleID) { return Color(nsColor: c) }
        return item.kind.tint
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let icon = ImageCache.shared.appIcon(bundleID: item.sourceBundleID) {
                    Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                } else {
                    Image(systemName: item.kind.symbol).font(.system(size: 16, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.kind.label).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).opacity(0.85)
                }
                Spacer()
                Text(L("Space to close", "按空白鍵關閉")).font(.system(size: 11)).opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(headerColor)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        .padding(1)
    }

    private var subtitle: String {
        var parts = [RelativeTime.string(for: item.date)]
        if let app = item.sourceAppName { parts.insert(app, at: 0) }
        parts.append(item.detail)
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text, .link:
            textScroll(AttributedString(item.text))
        case .richText:
            textScroll(richText ?? AttributedString(item.text))
        case .image:
            if let img = NSImage(contentsOf: Store.shared.blobURL(item.id, "png")) {
                Image(nsImage: img).resizable().scaledToFit().padding(12)
            } else {
                Image(systemName: "photo").font(.system(size: 48)).foregroundStyle(.secondary)
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(item.filePaths, id: \.self) { path in
                        HStack(spacing: 12) {
                            Image(nsImage: ImageCache.shared.fileIcon(path: path))
                                .resizable().frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((path as NSString).lastPathComponent).font(.system(size: 14, weight: .medium))
                                Text((path as NSString).deletingLastPathComponent)
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        case .color:
            let ns = ColorParser.parse(item.text) ?? .gray
            ZStack {
                Color(nsColor: ns)
                Text(item.text)
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ns.isLight ? Color.black.opacity(0.8) : Color.white)
            }
        }
    }

    private func textScroll(_ text: AttributedString) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(18)
        }
    }

    private var richText: AttributedString? {
        let store = Store.shared
        if let rtf = store.blobData(item.id, "rtf"),
           let ns = NSAttributedString(rtf: rtf, documentAttributes: nil),
           let a = try? AttributedString(ns, including: \.appKit) {
            return a
        }
        return nil
    }
}
