import AppKit
import Combine
import SwiftUI

/// A non-activating panel must deliver the first click to SwiftUI, even while
/// another app owns keyboard focus. Otherwise the first click only activates it.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
}

/// One owner for dwell, exit grace and explicit dismissal. View transitions
/// must never create independent close timers or reopen a just-closed panel.
struct NotchHoverGate {
    private(set) var inside = false
    private(set) var suppressed = false

    mutating func update(inside value: Bool) {
        inside = value
        if !value { suppressed = false }
    }

    mutating func dismiss() { suppressed = inside }
    var canOpen: Bool { inside && !suppressed }
}

@MainActor
final class NotchPanelCoordinator {
    private let state: JendelaState
    let panel: InteractiveNotchPanel
    private var cancellables = Set<AnyCancellable>()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var pending: DispatchWorkItem?
    private var gate = NotchHoverGate()
    private var renderedExpanded = false
    /// Shrinks the panel once the closing animation has finished.
    private var settle: DispatchWorkItem?
    /// Set between a layout request and the pass that serves it.
    private var layoutScheduled = false

    init(state: JendelaState) {
        self.state = state
        panel = InteractiveNotchPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Jendela Notch"
        panel.identifier = NSUserInterfaceItemIdentifier("widgetmac.notch")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // The coordinator owns the panel's geometry.
        //
        // A hosting view set directly as `contentView` pushes its own fitting
        // size onto the window: opening the hub produced a setFrame to the
        // card's size (no shadow inset, no side padding) immediately before
        // ours, which showed up as a flicker. Nesting it inside a plain view
        // keeps that size from ever reaching the window.
        let host = FirstClickHostingView(rootView: NotchPanelView(state: state))
        host.sizingOptions = []
        let container = NSView()
        container.autoresizesSubviews = true
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container
        host.frame = container.bounds
        state.pointerAtNotch = { [weak self] _ in self?.updatePointer() }
        state.dismissNotch = { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            self.pending = nil
            self.gate.dismiss()
        }

        state.$notchExpanded.combineLatest(state.$notchSize,
            state.$selectedSection, state.$visibleClipboardCount)
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleLayout() }
            .store(in: &cancellables)
        state.$notchPinned.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePointer(force: true) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.scheduleLayout() }.store(in: &cancellables)

        // Event-driven only: no mouse-position polling or display-link timer.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53, self.state.notchExpanded {
                self.state.closeNotch()
                return nil
            }
            if event.type == .leftMouseDown, event.window === self.panel {
                if self.state.notchExpanded { self.panel.makeKey() }
                else { self.state.openNotch(); return nil }
            } else if event.type == .leftMouseDown, self.state.notchExpanded, !self.state.holdsOpen {
                self.state.closeNotch()
            }
            self.updatePointer()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .leftMouseDown, self.state.notchExpanded {
                    // A non-activating panel keeps first-responder status even
                    // when the click lands elsewhere, so the chat field stayed
                    // "focused" and held the hub open forever. Clicking outside
                    // gives that focus up explicitly.
                    if self.state.chatFocused {
                        self.state.chatFocused = false
                        self.panel.makeFirstResponder(nil)
                    }
                    if !self.state.holdsOpen { self.state.closeNotch() }
                }
                self.updatePointer()
            }
        }
        layout()
    }

    func show() { panel.orderFrontRegardless() }

    /// Where the card is actually drawn, which is not always the panel's frame:
    /// while the card animates closed the panel is deliberately still large.
    /// Pointer tests use this, so hit testing keeps matching what is on screen.
    private var visibleRect: NSRect {
        guard let screen = targetScreen else { return panel.frame }
        let size = state.notchExpanded
            ? NotchMetrics.expandedSize(for: state.selectedSection,
                clipboardCount: state.visibleClipboardCount, size: state.notchSize, width: state.hubWidth, shelfCount: state.shelfItems.count)
            : NotchMetrics.compactSize(on: screen)
        return NotchMetrics.topAlignedFrame(size, on: screen)
    }

    private var targetScreen: NSScreen? {
        panel.screen ?? NSScreen.screens.first(where: { NotchMetrics.notch(on: $0).isReal }) ?? NSScreen.main
    }

    /// Four publishers feed the layout and several of them change together, so
    /// opening the hub used to set the window frame twice in the same run loop
    /// turn. Coalescing to one pass removes that flicker.
    private func scheduleLayout() {
        guard !layoutScheduled else { return }
        layoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutScheduled = false
            self.layout()
        }
    }

    private func layout() {
        guard let screen = targetScreen else { return }
        settle?.cancel()
        settle = nil

        let target = NotchMetrics.topAlignedFrame(
            state.notchExpanded
                ? NotchMetrics.expandedSize(for: state.selectedSection,
                    clipboardCount: state.visibleClipboardCount, size: state.notchSize, width: state.hubWidth, shelfCount: state.shelfItems.count)
                : NotchMetrics.compactSize(on: screen),
            on: screen
        )

        // Grow now, shrink later — for *every* size change, not just closing.
        //
        // Switching from a tall tab to a short one (Clipboard to Sound, say) is
        // a shrink too. Applying that immediately clipped the card while it was
        // still animating down, which is what made tab switches look like a
        // jump rather than a resize.
        let current = panel.frame
        let union = NSRect(
            x: min(current.minX, target.minX),
            y: min(current.minY, target.minY),
            width: max(current.width, target.width),
            height: max(current.height, target.height)
        )
        // Keep the union pinned to the top of the screen like everything else.
        let held = NSRect(
            x: union.minX,
            y: screen.frame.maxY - union.height,
            width: union.width,
            height: union.height
        )

        if held != current { panel.setFrame(held, display: true, animate: false) }

        if held == target {
            panel.ignoresMouseEvents = false
        } else {
            // While the panel is larger than the card, stop it swallowing
            // clicks on the area the card no longer occupies.
            panel.ignoresMouseEvents = !state.notchExpanded
            let work = DispatchWorkItem { [weak self] in
                guard let self, let screen = self.targetScreen else { return }
                let settled = NotchMetrics.topAlignedFrame(
                    self.state.notchExpanded
                        ? NotchMetrics.expandedSize(for: self.state.selectedSection,
                            clipboardCount: self.state.visibleClipboardCount, size: self.state.notchSize, width: self.state.hubWidth, shelfCount: self.state.shelfItems.count)
                        : NotchMetrics.compactSize(on: screen),
                    on: screen
                )
                self.panel.setFrame(settled, display: true, animate: false)
                self.panel.ignoresMouseEvents = false
            }
            settle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchMetrics.morphDuration, execute: work)
        }

        if renderedExpanded && !state.notchExpanded { panel.resignKey() }
        renderedExpanded = state.notchExpanded
        panel.orderFrontRegardless()
    }

    private func updatePointer(force: Bool = false) {
        guard NSEvent.pressedMouseButtons == 0 else { return } // keep clipboard drag alive
        let point = NSEvent.mouseLocation
        let inside = visibleRect.contains(point)
        let changed = gate.inside != inside
        guard changed || force else { return }
        gate.update(inside: inside)
        state.notchHovered = inside
        pending?.cancel()
        pending = nil
        if inside {
            guard gate.canOpen, state.expandOnHover, !state.notchExpanded else { return }
            schedule(after: 0.10) { owner in
                guard owner.gate.canOpen, owner.state.expandOnHover else { return }
                owner.state.notchPinned = false
                owner.state.notchExpanded = true
            }
        } else if state.notchExpanded {
            scheduleExitClose()
        }
    }

    /// Closes once the pointer is away. If the chat is mid-sentence the check
    /// simply comes back around, so typing is never interrupted but an
    /// abandoned field does not hold the hub open indefinitely.
    private func scheduleExitClose(after delay: TimeInterval = 0.30) {
        pending?.cancel()
        schedule(after: delay) { owner in
            guard !owner.visibleRect.contains(NSEvent.mouseLocation),
                  NSEvent.pressedMouseButtons == 0 else { return }
            guard !owner.state.holdsOpen else {
                owner.scheduleExitClose(after: 1.0)
                return
            }
            owner.state.chatFocused = false
            owner.panel.makeFirstResponder(nil)
            owner.state.notchExpanded = false
        }
    }

    private func schedule(after delay: TimeInterval, action: @escaping (NotchPanelCoordinator) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            action(self)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}


extension NSRect {
    /// Brings a saved window position back onto an attached display.
    ///
    /// Frames are restored from the settings file, and `InteractiveNotchPanel`
    /// deliberately disables AppKit's own constraining so the hub can sit in
    /// the menu bar. Anything else built on that panel inherits it, so a window
    /// last positioned on a display that is no longer attached came back
    /// off-screen — reported visible, drawn nowhere, and unreachable without
    /// editing settings by hand.
    ///
    /// A window only needs enough of itself on screen to be grabbed, so a
    /// deliberately half-off-screen position is left alone.
    func nudgedOntoScreen(minimumVisible: CGSize = CGSize(width: 120, height: 60)) -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return self }

        let reachable = screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(self)
            return overlap.width >= Swift.min(minimumVisible.width, width)
                && overlap.height >= Swift.min(minimumVisible.height, height)
        }
        if reachable { return self }

        let target = (NSScreen.main ?? screens[0]).visibleFrame
        var rect = self
        rect.size.width = Swift.min(width, target.width)
        rect.size.height = Swift.min(height, target.height)
        rect.origin.x = (target.midX - rect.width / 2).rounded()
        rect.origin.y = (target.midY - rect.height / 2).rounded()
        return rect
    }
}
