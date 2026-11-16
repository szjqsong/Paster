import AppKit
import Combine

enum BoardEdit: Equatable {
    case new
    case rename(UUID)
}

/// State and keyboard behaviour of the bottom card strip.
final class PanelModel: ObservableObject {
    let store = Store.shared

    @Published var query = "" { didSet { if query != oldValue { selectedID = nil; previewItem = nil } } }
    @Published var boardID: UUID? { didSet { if boardID != oldValue { selectedID = nil; previewItem = nil } } }
    @Published var typeFilter: TypeFilter = .all { didSet { if typeFilter != oldValue { selectedID = nil; previewItem = nil } } }
    /// nil means "the first visible card".
    @Published var selectedID: UUID?
    @Published var previewItem: ClipItem?
    @Published var boardEdit: BoardEdit?
    @Published var boardNameDraft = ""
    /// Item waiting to be pinned to a pinboard that is being created.
    var pendingPinItem: ClipItem?

    weak var searchField: NSTextField?
    weak var window: NSWindow?

    var onPaste: ((ClipItem, Bool) -> Void)?
    var onCopy: ((ClipItem) -> Void)?
    var onClose: (() -> Void)?
    var onOpenPreferences: (() -> Void)?

    var visibleItems: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.items.filter { item in
            item.pinboardID == boardID
                && typeFilter.matches(item.kind)
                && (q.isEmpty || item.matches(query: q))
        }
    }

    func selectedIndex(in items: [ClipItem]) -> Int? {
        guard !items.isEmpty else { return nil }
        if let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) { return idx }
        return 0
    }

    var selectedItem: ClipItem? {
        let items = visibleItems
        guard let idx = selectedIndex(in: items) else { return nil }
        return items[idx]
    }

    func prepareForShow() {
        query = ""
        typeFilter = .all
        boardEdit = nil
        previewItem = nil
        selectedID = nil
        if let b = boardID, !store.pinboards.contains(where: { $0.id == b }) { boardID = nil }
    }

    func focusSearch() {
        guard let field = searchField, let window else { return }
        if window.firstResponder !== field.currentEditor() {
            window.makeFirstResponder(field)
        }
    }

    // MARK: Actions

    func select(_ item: ClipItem) {
        selectedID = item.id
        if previewItem != nil { previewItem = item }
    }

    func move(_ delta: Int, toEdge: Bool = false) {
        let items = visibleItems
        guard let idx = selectedIndex(in: items) else { return }
        let target: Int
        if toEdge { target = delta < 0 ? 0 : items.count - 1 }
        else { target = min(max(idx + delta, 0), items.count - 1) }
        selectedID = items[target].id
        if previewItem != nil { previewItem = items[target] }
    }

    func paste(_ item: ClipItem, plain: Bool) {
        previewItem = nil
        onPaste?(item, plain)
    }

    func copy(_ item: ClipItem) {
        previewItem = nil
        onCopy?(item)
    }

    func togglePreview() {
        if previewItem != nil { previewItem = nil } else { previewItem = selectedItem }
    }

    func delete(_ item: ClipItem) {
        let items = visibleItems
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            let next = idx + 1 < items.count ? items[idx + 1] : (idx > 0 ? items[idx - 1] : nil)
            selectedID = next?.id
            if previewItem != nil { previewItem = next }
        }
        store.delete(item.id)
    }

    func cycleBoard(_ delta: Int) {
        let ids: [UUID?] = [nil] + store.pinboards.map { Optional($0.id) }
        let idx = ids.firstIndex(of: boardID) ?? 0
        boardID = ids[(idx + delta + ids.count) % ids.count]
    }

    // MARK: Pinboard editing

    func beginNewBoard(pinning item: ClipItem? = nil) {
        pendingPinItem = item
        boardNameDraft = ""
        boardEdit = .new
    }

    func beginRename(_ board: Pinboard) {
        boardNameDraft = board.name
        boardEdit = .rename(board.id)
    }

    func commitBoardEdit() {
        let name = boardNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch boardEdit {
        case .new:
            if !name.isEmpty {
                let board = store.addPinboard(name: name)
                if let item = pendingPinItem { store.pin(item, to: board.id) } else { boardID = board.id }
            }
        case .rename(let id):
            if !name.isEmpty { store.renamePinboard(id, to: name) }
        case nil:
            break
        }
        cancelBoardEdit()
    }

    func cancelBoardEdit() {
        boardEdit = nil
        pendingPinItem = nil
        DispatchQueue.main.async { [weak self] in self?.focusSearch() }
    }

    func deleteBoard(_ board: Pinboard) {
        if boardID == board.id { boardID = nil }
        store.deletePinboard(board.id)
    }

    // MARK: Keyboard

    private static let digitKeyCodes: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]

    /// Returns true when the event was consumed. Anything not consumed falls through to the
    /// search field, which gives search-as-you-type (including input-method composition).
    func handleKey(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
        let code = e.keyCode

        if boardEdit != nil {
            if code == 53 { cancelBoardEdit(); return true }
            return false
        }
        // Never steal keys from an active input-method composition (e.g. Zhuyin / Pinyin).
        if let editor = window?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }

        switch code {
        case 53: // Esc
            if previewItem != nil { previewItem = nil }
            else if !query.isEmpty { query = "" }
            else { onClose?() }
            return true
        case 123: move(-1, toEdge: flags.contains(.command)); return true
        case 124: move(1, toEdge: flags.contains(.command)); return true
        case 36, 76: // Return / Enter
            if let item = selectedItem { paste(item, plain: flags.contains(.shift)) }
            return true
        case 49: // Space
            if flags.isEmpty && (query.isEmpty || previewItem != nil) { togglePreview(); return true }
            return false
        case 48: // Tab
            cycleBoard(flags.contains(.shift) ? -1 : 1)
            return true
        case 117: // Forward delete
            if let item = selectedItem { delete(item) }
            return true
        case 51 where flags == .command: // ⌘⌫
            if let item = selectedItem { delete(item) }
            return true
        default:
            break
        }

        if flags == .command {
            if let n = PanelModel.digitKeyCodes[code] {
                let items = visibleItems
                if n < items.count { paste(items[n], plain: false) }
                return true
            }
            switch code {
            case 8: // ⌘C — copy without pasting (unless text is selected in the search field)
                if let editor = window?.firstResponder as? NSTextView, editor.selectedRange().length > 0 { return false }
                if let item = selectedItem { copy(item) }
                return true
            case 3: focusSearch(); searchField?.selectText(nil); return true // ⌘F
            case 43: onOpenPreferences?(); return true // ⌘,
            case 45: beginNewBoard(); return true // ⌘N
            default: break
            }
        }
        if flags == [.command, .shift], let n = PanelModel.digitKeyCodes[code] {
            let items = visibleItems
            if n < items.count { paste(items[n], plain: true) }
            return true
        }
        // Plain typing: make sure it lands in the search field.
        if flags.subtracting(.shift).isEmpty { focusSearch() }
        return false
    }
}
