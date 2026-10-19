import AppKit

/// Colors for the tab strip, derived from the current page so the strip blends into it.
struct StripPalette {
    var background: NSColor
    var foreground: NSColor
    /// Applied to the strip so spinners and symbols render for a light or dark background.
    var appearance: NSAppearance?

    static let standard = StripPalette(background: .windowBackgroundColor, foreground: .labelColor, appearance: nil)

    init(background: NSColor, foreground: NSColor, appearance: NSAppearance?) {
        self.background = background
        self.foreground = foreground
        self.appearance = appearance
    }

    init(pageColor: NSColor?) {
        guard let rgb = pageColor?.usingColorSpace(.sRGB), rgb.alphaComponent > 0.5 else {
            self = .standard
            return
        }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        let isDark = luminance < 0.55
        self.init(
            background: rgb.withAlphaComponent(1),
            foreground: isDark ? .white : .black,
            appearance: NSAppearance(named: isDark ? .darkAqua : .aqua)
        )
    }
}

/// The row at the top of the window: room for the traffic lights, then the tabs and a "+" button.
/// Empty space drags the window and double-click zooms it, like a normal title bar.
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

    private static let maxTabWidth: CGFloat = 240
    private static let minTabWidth: CGFloat = 72
    private static let tabSpacing: CGFloat = 4
    private static let verticalInset: CGFloat = 5

    override init(frame: NSRect) {
        super.init(frame: frame)
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        newTabButton.isBordered = false
        newTabButton.imagePosition = .imageOnly
        newTabButton.toolTip = "New Tab (⌘T)"
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked)
        addSubview(newTabButton)
        applyPalette()
    }

    private func applyPalette() {
        appearance = palette.appearance
        newTabButton.contentTintColor = palette.foreground.withAlphaComponent(0.75)
        tabViews.forEach { $0.palette = palette }
        needsDisplay = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let buttonSize: CGFloat = 26
        let trailingPadding: CGFloat = 10
        let available = bounds.width - leadingInset - trailingPadding - buttonSize - Self.tabSpacing * 2
        let count = CGFloat(max(tabViews.count, 1))
        let width = min(Self.maxTabWidth, max(Self.minTabWidth, (available - Self.tabSpacing * (count - 1)) / count))

        var x = leadingInset
        for view in tabViews {
            view.frame = NSRect(
                x: x, y: Self.verticalInset,
                width: width, height: bounds.height - Self.verticalInset * 2
            ).integral
            x += width + Self.tabSpacing
        }
        newTabButton.frame = NSRect(
            x: min(x + Self.tabSpacing, bounds.width - trailingPadding - buttonSize),
            y: (bounds.height - buttonSize) / 2,
            width: buttonSize, height: buttonSize
        ).integral
        onLayout?()
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.background.setFill()
        dirtyRect.fill()
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

/// A single tab: title, loading spinner, and a close button shown on hover or when selected.
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

    override init(frame: NSRect) {
        super.init(frame: frame)

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        addSubview(titleLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        addSubview(spinner)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
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
        needsLayout = true
    }

    private func applyColors() {
        titleLabel.textColor = palette.foreground.withAlphaComponent(isSelected ? 0.95 : 0.65)
        closeButton.contentTintColor = palette.foreground.withAlphaComponent(0.7)
        closeButton.isHidden = !(isSelected || isHovered)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 10
        let iconSize: CGFloat = 16
        let midY = bounds.midY

        var leading = padding
        if isLoading {
            spinner.frame = NSRect(x: leading, y: midY - 7, width: 14, height: 14)
            leading += 14 + 6
        }
        closeButton.frame = NSRect(x: bounds.width - padding - iconSize + 4, y: midY - iconSize / 2, width: iconSize, height: iconSize)
        let trailing = bounds.width - padding - iconSize - 2
        let labelHeight = titleLabel.intrinsicContentSize.height
        titleLabel.frame = NSRect(x: leading, y: midY - labelHeight / 2, width: max(0, trailing - leading), height: labelHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected || isHovered else { return }
        palette.foreground.withAlphaComponent(isSelected ? 0.13 : 0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
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
