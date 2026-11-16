import AppKit
import SwiftUI
import Combine

/// Borderless, non-activating panel: it can take keyboard focus without activating Paster,
/// so the application the user was working in stays frontmost and receives the paste.
final class StripPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class PanelController: NSObject, NSWindowDelegate {
    static let panelHeight: CGFloat = 372

    let model = PanelModel()
    private let panel: StripPanel
    private let previewPanel: NSPanel
    private var previewHost: NSHostingView<AnyView>?
    private(set) var isVisible = false
    private var isAnimatingOut = false
    private var previousApp: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private var scrollMonitor: Any?

    override init() {
        panel = StripPanel(contentRect: NSRect(x: 0, y: 0, width: 1200, height: PanelController.panelHeight),
                           styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                           backing: .buffered, defer: false)
        previewPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.delegate = self

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        let host = NSHostingView(rootView: PanelView(model: model))
        host.sizingOptions = []
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        panel.contentView = effect

        previewPanel.level = .statusBar
        previewPanel.isOpaque = false
        previewPanel.backgroundColor = .clear
        previewPanel.hasShadow = true
        previewPanel.isReleasedWhenClosed = false
        previewPanel.hidesOnDeactivate = false
        previewPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        model.window = panel
        panel.keyHandler = { [weak self] event in self?.model.handleKey(event) ?? false }
        model.onClose = { [weak self] in self?.hide() }
        model.onPaste = { [weak self] item, plain in self?.paste(item, plain: plain) }
        model.onCopy = { [weak self] item in
            PasteService.write(item, plainText: false)
            self?.hide()
        }
        model.onOpenPreferences = { [weak self] in
            self?.hide()
            PreferencesWindowController.shared.show()
        }
        model.$previewItem
            .removeDuplicates()
            .sink { [weak self] item in self?.updatePreview(item) }
            .store(in: &cancellables)

        // Let a vertical mouse wheel scroll the horizontal card strip.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel,
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  let cg = event.cgEvent?.copy() else { return event }
            let intPairs: [(CGEventField, CGEventField)] = [
                (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
                (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
            ]
            for (v, h) in intPairs {
                cg.setIntegerValueField(h, value: cg.getIntegerValueField(v))
                cg.setIntegerValueField(v, value: 0)
            }
            let fixed = cg.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed)
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
            return NSEvent(cgEvent: cg) ?? event
        }
    }

    // MARK: Show / hide

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    func show() {
        guard !isVisible, let screen = targetScreen() else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        model.prepareForShow()
        // Keep clipboard contents out of screen recordings / screen sharing.
        let sharing: NSWindow.SharingType = Settings.shared.hideFromScreenSharing ? .none : .readOnly
        panel.sharingType = sharing
        previewPanel.sharingType = sharing
        isVisible = true
        isAnimatingOut = false

        let h = PanelController.panelHeight
        let final = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: h)
        var start = final
        start.origin.y -= h
        panel.setFrame(start, display: true)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        model.focusSearch()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(final, display: true)
        }
        DispatchQueue.main.async { [weak self] in self?.model.focusSearch() }
    }

    func hide(completion: (() -> Void)? = nil) {
        guard isVisible, !isAnimatingOut else { completion?(); return }
        isAnimatingOut = true
        model.previewItem = nil
        var end = panel.frame
        end.origin.y -= end.height
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.isVisible = false
            self.isAnimatingOut = false
            completion?()
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere outside the strip dismisses it.
        if isVisible { hide() }
    }

    // MARK: Paste

    private func paste(_ item: ClipItem, plain: Bool) {
        let settings = Settings.shared
        // ⇧ inverts the "always paste as plain text" preference.
        let plainText = plain != settings.plainTextByDefault
        PasteService.write(item, plainText: plainText)
        let target = previousApp
        hide {
            if settings.pasteDirectly {
                PasteService.sendPaste(to: target)
            }
        }
    }

    // MARK: Quick preview

    private func updatePreview(_ item: ClipItem?) {
        guard let item, isVisible else {
            if previewPanel.parent != nil { panel.removeChildWindow(previewPanel) }
            previewPanel.orderOut(nil)
            return
        }
        let view = AnyView(PreviewView(item: item).id(item.id))
        if let host = previewHost {
            host.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            previewPanel.contentView = host
            previewHost = host
        }
        let screen = panel.screen ?? NSScreen.main
        let sf = screen?.frame ?? panel.frame
        let stripTop = sf.minY + PanelController.panelHeight
        let available = sf.maxY - stripTop - 60
        let w = min(820, sf.width - 80)
        let h = max(220, min(540, available))
        let frame = NSRect(x: sf.midX - w / 2, y: stripTop + 20, width: w, height: h)
        previewPanel.setFrame(frame, display: true)
        if previewPanel.parent == nil {
            panel.addChildWindow(previewPanel, ordered: .above)
        }
        previewPanel.orderFront(nil)
    }
}
