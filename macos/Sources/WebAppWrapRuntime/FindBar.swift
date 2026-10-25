import AppKit

/// The floating Find box at the top right of the page (⌘F). It only gathers input; the
/// window does the searching (see BrowserWindowController's Find section).
final class FindBar: NSVisualEffectView, NSSearchFieldDelegate {
    var onChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    let field = NSSearchField()
    private let resultLabel = NSTextField(labelWithString: "")

    var query: String { field.stringValue }

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        shadow = {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 8
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            return shadow
        }()

        field.placeholderString = "Find on Page"
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = self
        field.target = self
        field.action = #selector(fieldChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true

        resultLabel.textColor = .secondaryLabelColor
        resultLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        resultLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let previous = Self.button("chevron.up", "Previous Match (⇧⌘G)", #selector(previousPressed))
        let next = Self.button("chevron.down", "Next Match (⌘G)", #selector(nextPressed))
        let done = Self.button("xmark", "Done (Esc)", #selector(closePressed))
        for button in [previous, next, done] { button.target = self }

        let stack = NSStackView(views: [field, resultLabel, previous, next, done])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func button(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: action)
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.toolTip = label
        return button
    }

    /// nil clears it; otherwise e.g. "3 matches" or "Not found".
    func showResult(_ text: String?) {
        resultLabel.stringValue = text ?? ""
        resultLabel.isHidden = text == nil
    }

    @objc private func fieldChanged(_ sender: NSSearchField) { onChange?(sender.stringValue) }
    @objc private func nextPressed() { onNext?() }
    @objc private func previousPressed() { onPrevious?() }
    @objc private func closePressed() { onClose?() }

    /// Return finds the next match (⇧Return the previous one) and Esc closes the box.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { onPrevious?() } else { onNext?() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }
}
