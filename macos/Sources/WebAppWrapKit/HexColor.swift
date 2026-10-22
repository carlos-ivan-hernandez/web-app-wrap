import Foundation

/// An sRGB color stored as "#RRGGBB" in a generated app's Info.plist.
public struct HexColor: Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    /// The title bar color used when none is chosen.
    public static let defaultTitleBar = HexColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255)

    /// The color behind an SVG icon when none is chosen.
    public static let defaultIconBackground = HexColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255)

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Accepts "#1a1a1a", "1A1A1A" or the short form "#fff".
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    public var hexString: String {
        let channels = [red, green, blue].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }

    /// Relative luminance; below ~0.5 a color is dark enough to need light text.
    public var luminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    public var isDark: Bool { luminance < 0.5 }
}
