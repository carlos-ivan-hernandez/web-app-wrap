import AppKit
import WebAppWrapKit

/// Colors for the tab bar, from the title bar color chosen in WebAppWrap.
struct StripPalette {
    var background: NSColor
    var foreground: NSColor
    /// Applied to the strip so spinners and symbols render for a light or dark background.
    var appearance: NSAppearance?

    init(color: HexColor) {
        background = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        foreground = color.isDark ? .white : .black
        appearance = NSAppearance(named: color.isDark ? .darkAqua : .aqua)
    }

    static let standard = StripPalette(color: .defaultTitleBar)
}

/// The bar at the top of the window: room for the traffic lights, then the tabs and a "+",
/// and on the right the Extensions and More buttons (`trailingAccessory`).
/// With a single tab it's just a plain title bar. With more, tabs up to 240pt wide (shrinking
/// to fit when there are many) sit side by side between thin dividers. Empty space drags the
/// window and double-click zooms it. Tabs can be dragged sideways to reorder them.
final class TabStripView: NSView {
    struct Item {
        var title: String
        var isLoading: Bool
    }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onLayout: (() -> Void)?
    /// A tab was dragged from one index to another.
    var onMove: ((_ from: Int, _ to: Int) -> Void)?

    /// Space reserved on the left for the traffic lights.
    var leadingInset: CGFloat = 80 { didSet { needsLayout = true } }

    var palette = StripPalette.standard {
        didSet { applyPalette() }
    }

    /// Shown at the right end of the bar, sized to fit. Holds the Extensions and More buttons.
    var trailingAccessory: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let trailingAccessory { addSubview(trailingAccessory) }
            needsLayout = true
        }
    }

    private var accessoryWidth: CGFloat {
        guard let trailingAccessory, !trailingAccessory.isHidden else { return 0 }
        return ceil(trailingAccessory.fittingSize.width)
    }

    private var tabViews: [TabItemView] = []
    private let newTabButton = NSButton()
    private var showsTabs: Bool { tabViews.count > 1 }
    /// The tab under the mouse during a drag; layout leaves it where the mouse put it.
    private var draggedView: TabItemView?

    private static let maxTabWidth: CGFloat = 240
    private static let minTabWidth: CGFloat = 72
    private static let newTabButtonWidth: CGFloat = 36
    private static let trailingPadding: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        newTabButton.isBordered = false
        newTabButton.imagePosition = .imageOnly
        newTabButton.toolTip = "New Tab (⌘T)"
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked)
        addSubview(newTabButton)
        applyPalette()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func applyPalette() {
        appearance = palette.appearance
        newTabButton.contentTintColor = palette.foreground.withAlphaComponent(0.5)
        tabViews.forEach { $0.palette = palette }
        needsDisplay = true
    }

    func update(items: [Item], selectedIndex: Int?) {
        while tabViews.count < items.count {
            let view = TabItemView()
            view.palette = palette
            addSubview(view)
            tabViews.append(view)
        }
        while tabViews.count > items.count {
            tabViews.removeLast().removeFromSuperview()
        }
        for (index, (view, item)) in zip(tabViews, items).enumerated() {
            view.configure(title: item.title, isLoading: item.isLoading, isSelected: index == selectedIndex)
            view.onSelect = { [weak self] in self?.onSelect?(index) }
            view.onClose = { [weak self] in self?.onClose?(index) }
        }
        tabViews.forEach { $0.isHidden = !showsTabs }
        newTabButton.isHidden = !showsTabs
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        for (index, view) in tabViews.enumerated() where view !== draggedView {
            view.frame = tabFrame(at: index)
        }
        // Right after the last tab, but never pushed off the edge when tabs are at minimum width.
        let afterTabs = (leadingInset + CGFloat(tabViews.count) * tabWidth).rounded()
        newTabButton.frame = NSRect(
            x: min(afterTabs, bounds.width - accessoryWidth - Self.newTabButtonWidth - Self.trailingPadding), y: 0,
            width: Self.newTabButtonWidth, height: bounds.height
        )
        trailingAccessory?.frame = NSRect(
            x: bounds.width - accessoryWidth - Self.trailingPadding, y: 0,
            width: accessoryWidth, height: bounds.height
        )
        onLayout?()
    }

    private var tabWidth: CGFloat {
        let available = bounds.width - leadingInset - accessoryWidth - Self.newTabButtonWidth - Self.trailingPadding
        let fitted = available / CGFloat(max(tabViews.count, 1))
        return min(Self.maxTabWidth, max(Self.minTabWidth, fitted))
    }

    private func tabFrame(at index: Int) -> NSRect {
        let minX = (leadingInset + CGFloat(index) * tabWidth).rounded()
        let maxX = (leadingInset + CGFloat(index + 1) * tabWidth).rounded()
        return NSRect(x: minX, y: 0, width: maxX - minX, height: bounds.height)
    }

    // MARK: - Selecting and dragging tabs

    /// Handles a press on a tab: selects it, and if the mouse then moves sideways, drags the tab
    /// along the bar, sliding the others out of the way, until the button is released.
    fileprivate func trackPress(on view: TabItemView, with event: NSEvent) {
        guard let startIndex = tabViews.firstIndex(where: { $0 === view }) else { return }
        onSelect?(startIndex)
        guard showsTabs, let window else { return }

        let startX = convert(event.locationInWindow, from: nil).x
        let grabOffset = startX - view.frame.minX
        var currentIndex = startIndex
        var isDragging = false

        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
            let x = convert(next.locationInWindow, from: nil).x
            if !isDragging {
                guard abs(x - startX) > 4 else { continue }
                isDragging = true
                draggedView = view
                addSubview(view, positioned: .above, relativeTo: nil)
            }

            // Follow the mouse, kept within the row of tabs.
            let lastSlot = tabFrame(at: tabViews.count - 1).minX
            view.setFrameOrigin(NSPoint(x: min(max(x - grabOffset, leadingInset), lastSlot), y: 0))

            // The slot under the dragged tab's center is where it would land.
            let slot = Int(((view.frame.midX - leadingInset) / tabWidth).rounded(.down))
            let target = min(max(slot, 0), tabViews.count - 1)
            if target != currentIndex {
                tabViews.remove(at: currentIndex)
                tabViews.insert(view, at: target)
                currentIndex = target
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    for (index, other) in tabViews.enumerated() where other !== view {
                        other.animator().frame = tabFrame(at: index)
                    }
                }
            }
            needsDisplay = true
        }

        guard isDragging else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            view.animator().frame = tabFrame(at: currentIndex)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.draggedView = nil
                self?.needsLayout = true
                self?.needsDisplay = true
            }
        })
        if currentIndex != startIndex {
            onMove?(startIndex, currentIndex)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.background.setFill()
        dirtyRect.fill()

        // Thin dividers on both sides of every tab, as in terminal-style tab bars.
        // Drawn at the resting slots, so they stay put while a tab is dragged across them.
        guard showsTabs else { return }
        palette.foreground.withAlphaComponent(0.12).setFill()
        let lineWidth = 1 / (window?.backingScaleFactor ?? 2)
        var edges = tabViews.indices.map { tabFrame(at: $0).minX }
        if !tabViews.isEmpty { edges.append(tabFrame(at: tabViews.count - 1).maxX) }
        for x in edges {
            NSRect(x: x - lineWidth / 2, y: 0, width: lineWidth, height: bounds.height).fill()
        }
    }

    @objc private func newTabClicked() {
        onNewTab?()
    }

    // MARK: - Title bar behavior

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Honor System Settings > Desktop & Dock > "Double-click a window's title bar to".
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window?.performMiniaturize(nil)
            case "None": break
            default: window?.performZoom(nil)
            }
        } else {
            dragWindow()
        }
    }

    /// Moves the window with the mouse until the button is released. Done by hand because the
    /// window is not movable (see BrowserWindowController), which keeps tabs from dragging it.
    private func dragWindow() {
        guard let window else { return }
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin

        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
            let mouse = NSEvent.mouseLocation
            var origin = NSPoint(x: startOrigin.x + mouse.x - startMouse.x, y: startOrigin.y + mouse.y - startMouse.y)
            // Like a normal window, don't let the bar slide up under the menu bar.
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? window.screen {
                origin.y = min(origin.y, screen.visibleFrame.maxY - window.frame.height)
            }
            window.setFrameOrigin(origin)
        }
    }
}

/// A single tab: a centered title, a loading spinner, and a close button shown when the tab
/// is selected or hovered. Its background is always the bar's; only the text marks selection.
private final class TabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    var palette = StripPalette.standard {
        didSet { applyColors() }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let spinner = NSProgressIndicator()
    private var isSelected = false
    private var isLoading = false
    private var isHovered = false {
        didSet { applyColors() }
    }

    /// Room kept clear on both sides so the title stays centered and never runs under the close button.
    private static let sideInset: CGFloat = 36

    override init(frame: NSRect) {
        super.init(frame: frame)

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        addSubview(titleLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        addSubview(spinner)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.toolTip = "Close Tab (⌘W)"
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(title: String, isLoading: Bool, isSelected: Bool) {
        titleLabel.stringValue = title
        toolTip = title
        self.isSelected = isSelected
        if isLoading != self.isLoading {
            self.isLoading = isLoading
            isLoading ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        }
        applyColors()
    }

    private func applyColors() {
        titleLabel.textColor = palette.foreground.withAlphaComponent(isSelected ? 0.95 : 0.5)
        closeButton.contentTintColor = palette.foreground.withAlphaComponent(isSelected ? 0.9 : 0.5)
        closeButton.isHidden = !(isSelected || isHovered)
    }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        let labelHeight = titleLabel.intrinsicContentSize.height
        titleLabel.frame = NSRect(
            x: Self.sideInset, y: midY - labelHeight / 2,
            width: max(0, bounds.width - Self.sideInset * 2), height: labelHeight
        )
        spinner.frame = NSRect(x: 12, y: midY - 7, width: 14, height: 14)
        closeButton.frame = NSRect(x: bounds.width - 32, y: midY - 10, width: 20, height: 20)
    }

    // MARK: - Mouse

    override var mouseDownCanMoveWindow: Bool { false }

    /// Lets a tab be clicked or dragged even while the window is in the background.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        guard let strip = superview as? TabStripView else {
            onSelect?()
            return
        }
        strip.trackPress(on: self, with: event)
    }

    /// Middle-click closes, as in browsers.
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }

    @objc private func closeClicked() {
        onClose?()
    }
}

/// A borderless button at the right end of the tab bar (the Extensions and More menus), with a
/// soft highlight while the mouse is over it or its menu is open.
final class TitleBarButton: NSButton {
    var onPress: ((TitleBarButton) -> Void)?
    /// The highlight is drawn in this color, faintly. Set to the bar's text color.
    var hoverColor: NSColor = .white {
        didSet { needsDisplay = true }
    }

    private var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }
    private var isShowingMenu = false {
        didSet { needsDisplay = true }
    }

    static let size: CGFloat = 28

    init(image: NSImage?, label: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        self.image = image
        toolTip = label
        setAccessibilityLabel(label)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        target = self
        action = #selector(pressed)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered || isShowingMenu {
            hoverColor.withAlphaComponent(isShowingMenu ? 0.16 : 0.1).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }

    @objc private func pressed() {
        onPress?(self)
    }

    /// Shows `menu` just below the button, right-aligned with it, like a browser's toolbar
    /// menus. Returns once the menu closes.
    func popUp(_ menu: NSMenu) {
        isShowingMenu = true
        let x = bounds.maxX - menu.size.width
        let y = isFlipped ? bounds.maxY + 4 : bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: self)
        isShowingMenu = false
        // The mouse may have left while the menu was open, which sends no mouseExited.
        if let window {
            isHovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
    }

    /// Three vertical dots (a "kebab"), drawn here because SF Symbols' ellipsis is horizontal.
    static let kebabImage: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            let dot: CGFloat = 3.2
            for offset in [-5.0, 0.0, 5.0] {
                NSBezierPath(ovalIn: NSRect(
                    x: rect.midX - dot / 2, y: rect.midY - dot / 2 + CGFloat(offset),
                    width: dot, height: dot
                )).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "More"
        return image
    }()

    /// A grid of four rounded squares: "add-ons", without Chrome's puzzle piece.
    static let extensionsImage = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Extensions")?
        .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
}
