import SwiftUI
import AppKit

struct PanelView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store = Store.shared
    @ObservedObject var settings = Settings.shared

    var body: some View {
        let items = model.visibleItems
        let selectedIndex = model.selectedIndex(in: items)
        VStack(spacing: 0) {
            TopBar(model: model, store: store)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
            if items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                CardView(item: item, index: index, isSelected: index == selectedIndex,
                                         model: model, store: store)
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: model.selectedID) { id in
                        guard let id = id ?? items.first?.id else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                    }
                }
            }
            hints
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
            Text(emptyMessage).font(.system(size: 14))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if !model.query.isEmpty || model.typeFilter != .all {
            return L("No matching items", "找不到符合的項目")
        }
        if model.boardID != nil {
            return L("This pinboard is empty. Right-click a card and choose “Pin to”.",
                     "這個釘選板是空的。在卡片上按右鍵並選擇「釘選到」。")
        }
        if settings.paused { return L("Clipboard monitoring is paused", "剪貼簿監控已暫停") }
        return L("Copy something and it will show up here", "複製任何內容後就會出現在這裡")
    }

    private var hints: some View {
        HStack(spacing: 16) {
            hint("↩", L("Paste", "貼上"))
            hint("⇧↩", L("Plain text", "純文字貼上"))
            hint("⌘1–9", L("Quick paste", "快速貼上"))
            hint("Space", L("Preview", "預覽"))
            hint("⌘C", L("Copy", "拷貝"))
            hint("⌘⌫", L("Delete", "刪除"))
            hint("⇥", L("Switch pinboard", "切換釘選板"))
            hint("Esc", L("Close", "關閉"))
            Spacer()
            if settings.paused {
                Label(L("Paused", "已暫停"), systemImage: "pause.circle.fill").foregroundStyle(.orange)
            }
            if !PasteService.isTrusted && settings.pasteDirectly {
                Button {
                    PasteService.requestAccessibility()
                } label: {
                    Label(L("Grant Accessibility access to paste directly", "授予「輔助使用」權限以直接貼上"),
                          systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.yellow)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
        .frame(height: 24)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).fontWeight(.semibold)
            Text(label)
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                SearchField(model: model).frame(width: 190, height: 20)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.09)))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(title: L("Clipboard History", "剪貼簿歷史"), symbol: "clock.arrow.circlepath",
                         color: nil, selected: model.boardID == nil) { model.boardID = nil }
                    ForEach(store.pinboards) { board in
                        if model.boardEdit == .rename(board.id) {
                            nameEditor(color: board.color)
                        } else {
                            chip(title: board.name, symbol: nil, color: board.color,
                                 selected: model.boardID == board.id) { model.boardID = board.id }
                                .contextMenu {
                                    Button(L("Rename…", "重新命名⋯")) { model.beginRename(board) }
                                    Button(L("Delete Pinboard", "刪除釘選板"), role: .destructive) { model.deleteBoard(board) }
                                }
                        }
                    }
                    if model.boardEdit == .new {
                        nameEditor(color: .secondary)
                    }
                    Button { model.beginNewBoard() } label: {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(L("New Pinboard (⌘N)", "新增釘選板（⌘N）"))
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                ForEach(TypeFilter.allCases) { filter in
                    Button { model.typeFilter = filter } label: {
                        Image(systemName: filter.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(model.typeFilter == filter ? Color.accentColor.opacity(0.85) : Color.clear))
                            .foregroundStyle(model.typeFilter == filter ? Color.white : Color.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(filter.label)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.09)))

            Menu {
                Button(L("Preferences…", "偏好設定⋯")) { model.onOpenPreferences?() }
                Button(L("Clear Clipboard History", "清除剪貼簿歷史")) { store.clearHistory() }
                Divider()
                Button(L("Quit Paster", "結束 Paster")) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .frame(height: 34)
    }

    private func chip(title: String, symbol: String?, color: Color?, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                if let color { Circle().fill(color).frame(width: 9, height: 9) }
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(selected ? 0.16 : 0.0)))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func nameEditor(color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            TextField(L("Pinboard name", "釘選板名稱"), text: $model.boardNameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 130)
                .focused($nameFocused)
                .onSubmit { model.commitBoardEdit() }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 1.5))
        .onAppear { DispatchQueue.main.async { nameFocused = true } }
    }
}

/// AppKit text field so the panel can keep it focused and inspect input-method state.
struct SearchField: NSViewRepresentable {
    @ObservedObject var model: PanelModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = L("Type to search", "輸入以搜尋")
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        model.searchField = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.query {
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
            field.stringValue = model.query
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: PanelModel
        init(model: PanelModel) { self.model = model }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            if model.query != field.stringValue { model.query = field.stringValue }
        }
    }
}

// MARK: - Card

struct CardView: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    @ObservedObject var model: PanelModel
    @ObservedObject var store: Store
    @State private var lastClick = Date.distantPast

    static let size = CGSize(width: 268, height: 268)

    private var headerColor: Color {
        if item.kind == .color, let c = ColorParser.parse(item.text) { return Color(nsColor: c.withAlphaComponent(1)) }
        if let c = ImageCache.shared.appColor(bundleID: item.sourceBundleID) { return Color(nsColor: c) }
        return item.kind.tint
    }

    private var headerIsLight: Bool {
        if item.kind == .color, let c = ColorParser.parse(item.text) { return c.withAlphaComponent(1).isLight }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .frame(width: CardView.size.width, height: CardView.size.height)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                              lineWidth: isSelected ? 4 : 1)
        )
        .shadow(color: .black.opacity(isSelected ? 0.35 : 0.18), radius: isSelected ? 10 : 5, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            let now = Date()
            if isSelected && now.timeIntervalSince(lastClick) < NSEvent.doubleClickInterval {
                model.paste(item, plain: false)
            } else {
                model.select(item)
            }
            lastClick = now
        }
        .contextMenu { menu }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.kind.label).font(.system(size: 15, weight: .semibold))
                Text(RelativeTime.string(for: item.date)).font(.system(size: 11)).opacity(0.85)
            }
            .foregroundStyle(headerIsLight ? Color.black.opacity(0.8) : Color.white)
            Spacer(minLength: 0)
            if let icon = ImageCache.shared.appIcon(bundleID: item.sourceBundleID) {
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: 58, height: 58)
                    .offset(x: 10, y: 4)
                    .help(item.sourceAppName ?? "")
            } else {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 52)
        .background(headerColor)
        .clipped()
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text, .richText:
            Text(String(item.text.prefix(700)))
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
        case .link:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "link.circle.fill").font(.system(size: 26)).foregroundStyle(item.kind.tint)
                    Text(URL(string: item.text)?.host ?? item.text)
                        .font(.system(size: 14, weight: .semibold)).lineLimit(2)
                }
                Text(item.text).font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
        case .image:
            ZStack {
                Color.primary.opacity(0.06)
                if let img = ImageCache.shared.thumbnail(for: item) {
                    Image(nsImage: img).resizable().scaledToFit().padding(6)
                } else {
                    Image(systemName: "photo").font(.system(size: 36)).foregroundStyle(.secondary)
                }
            }
        case .file:
            VStack(spacing: 8) {
                Image(nsImage: ImageCache.shared.fileIcon(path: item.filePaths.first ?? ""))
                    .resizable().frame(width: 72, height: 72)
                Text(item.filePaths.map { ($0 as NSString).lastPathComponent }.prefix(3).joined(separator: "\n"))
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center).lineLimit(3)
                if item.filePaths.count > 3 {
                    Text(L("+\(item.filePaths.count - 3) more", "還有 \(item.filePaths.count - 3) 個"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
        case .color:
            let ns = ColorParser.parse(item.text) ?? .gray
            ZStack {
                Color(nsColor: ns)
                Text(item.text)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ns.isLight ? Color.black.opacity(0.8) : Color.white)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(item.detail).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if index < 9 {
                Text("⌘\(index + 1)").fontWeight(.medium)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var menu: some View {
        Button(L("Paste", "貼上")) { model.paste(item, plain: false) }
        Button(L("Paste as Plain Text", "以純文字貼上")) { model.paste(item, plain: true) }
        Button(L("Copy", "拷貝")) { model.copy(item) }
        Button(L("Quick Look", "快速預覽")) { model.selectedID = item.id; model.previewItem = item }
        if item.kind == .link, let url = URL(string: item.text) {
            Button(L("Open Link", "打開連結")) { NSWorkspace.shared.open(url); model.onClose?() }
        }
        if item.kind == .file, let first = item.filePaths.first {
            Button(L("Show in Finder", "在 Finder 中顯示")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: first)])
                model.onClose?()
            }
        }
        Divider()
        Menu(L("Pin to", "釘選到")) {
            ForEach(store.pinboards) { board in
                Button(board.name) { store.pin(item, to: board.id) }
            }
            if !store.pinboards.isEmpty { Divider() }
            Button(L("New Pinboard…", "新增釘選板⋯")) { model.beginNewBoard(pinning: item) }
        }
        Divider()
        Button(item.pinboardID == nil ? L("Delete", "刪除") : L("Remove from Pinboard", "從釘選板移除"),
               role: .destructive) { model.delete(item) }
    }
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func string(for date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 5 { return L("Just now", "剛剛") }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension NSColor {
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return lum > 0.6 || c.alphaComponent < 0.4
    }
}
