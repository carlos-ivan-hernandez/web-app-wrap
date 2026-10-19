import AppKit
import WebWrapKit

/// Colors for the tab bar, from the title bar color chosen in WebWrap.
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

/// The bar at the top of the window: room for the traffic lights, then the tabs and a "+".
/// With a single tab it's just a plain title bar. With more, tabs up to 240pt wide (shrinking
/// to fit when there are many) sit side by side between thin dividers. Empty space drags the
/// window and double-click zooms it.
final class TabStripView: NSView {
    struct Item {
        var title: String
        var isLoading: Bool
    }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onLayout: (() -> Void)?

    /// Space reserved on the left for the traffic lights.
    var leadingInset: CGFloat = 80 { didSet { needsLayout = true } }

    var palette = StripPalette.standard {
        didSet { applyPalette() }
    }

    private var tabViews: [TabItemView] = []
    private let newTabButton = NSButton()
    private var showsTabs: Bool { tabViews.count > 1 }

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
        let available = bounds.width - leadingInset - Self.newTabButtonWidth - Self.trailingPadding
        let fitted = available / CGFloat(max(tabViews.count, 1))
        let width = min(Self.maxTabWidth, max(Self.minTabWidth, fitted))

        for (index, view) in tabViews.enumerated() {
            let minX = (leadingInset + CGFloat(index) * width).rounded()
            let maxX = (leadingInset + CGFloat(index + 1) * width).rounded()
            view.frame = NSRect(x: minX, y: 0, width: maxX - minX, height: bounds.height)
        }
        // Right after the last tab, but never pushed off the edge when tabs are at minimum width.
        let afterTabs = (leadingInset + CGFloat(tabViews.count) * width).rounded()
        newTabButton.frame = NSRect(
            x: min(afterTabs, bounds.width - Self.newTabButtonWidth - Self.trailingPadding), y: 0,
            width: Self.newTabButtonWidth, height: bounds.height
        )
        onLayout?()
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.background.setFill()
        dirtyRect.fill()

        // Thin dividers on both sides of every tab, as in terminal-style tab bars.
        guard showsTabs else { return }
        palette.foreground.withAlphaComponent(0.12).setFill()
        let lineWidth = 1 / (window?.backingScaleFactor ?? 2)
        var edges = tabViews.map(\.frame.minX)
        if let last = tabViews.last { edges.append(last.frame.maxX) }
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
            window?.performDrag(with: event)
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
        onSelect?()
    }

    /// Middle-click closes, as in browsers.
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }

    @objc private func closeClicked() {
        onClose?()
    }
}
