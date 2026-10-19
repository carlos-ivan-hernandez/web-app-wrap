using System.Globalization;

namespace WebAppWrap.Core;

/// <summary>An sRGB color, stored as "#RRGGBB" in a wrapped app's settings.</summary>
public readonly record struct HexColor
{
    public double Red { get; }
    public double Green { get; }
    public double Blue { get; }

    /// <summary>The title bar color used when none is chosen and the site declares none.</summary>
    public static readonly HexColor DefaultTitleBar = new(0x1E / 255.0, 0x1E / 255.0, 0x1E / 255.0);

    public HexColor(double red, double green, double blue)
    {
        Red = Math.Clamp(red, 0, 1);
        Green = Math.Clamp(green, 0, 1);
        Blue = Math.Clamp(blue, 0, 1);
    }

    public static HexColor FromBytes(byte red, byte green, byte blue) => new(red / 255.0, green / 255.0, blue / 255.0);

    public byte R => (byte)Math.Round(Red * 255);
    public byte G => (byte)Math.Round(Green * 255);
    public byte B => (byte)Math.Round(Blue * 255);

    /// <summary>Accepts "#1a1a1a", "1A1A1A" or the short form "#fff".</summary>
    public static HexColor? FromHex(string? hex)
    {
        var text = hex?.Trim() ?? "";
        if (text.StartsWith('#')) text = text[1..];
        if (text.Length == 3) text = string.Concat(text.Select(c => $"{c}{c}"));
        if (text.Length != 6 || !uint.TryParse(text, NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out var value))
            return null;
        return FromBytes((byte)(value >> 16), (byte)(value >> 8), (byte)value);
    }

    /// <summary>
    /// Parses the CSS forms sites use for theme colors: #rgb, #rgba, #rrggbb, #rrggbbaa,
    /// rgb()/rgba() with numbers or percentages, and a few common names. Alpha is ignored.
    /// </summary>
    public static HexColor? FromCss(string? css)
    {
        var text = css?.Trim().ToLowerInvariant() ?? "";
        switch (text)
        {
            case "white": return new HexColor(1, 1, 1);
            case "black": return new HexColor(0, 0, 0);
        }

        if (text.StartsWith('#'))
        {
            var digits = text[1..];
            if (digits.Length == 4) digits = digits[..3];
            if (digits.Length == 8) digits = digits[..6];
            return FromHex(digits);
        }

        var open = text.IndexOf('(');
        var close = text.LastIndexOf(')');
        if (!text.StartsWith("rgb", StringComparison.Ordinal) || open < 0 || close < open) return null;
        var parts = text[(open + 1)..close]
            .Replace('/', ' ')
            .Split([',', ' '], StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 3) return null;

        static double? Channel(string part)
        {
            if (part.EndsWith('%'))
                return double.TryParse(part[..^1], NumberStyles.Float, CultureInfo.InvariantCulture, out var percent) ? percent / 100 : null;
            return double.TryParse(part, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ? value / 255 : null;
        }

        if (Channel(parts[0]) is not { } red || Channel(parts[1]) is not { } green || Channel(parts[2]) is not { } blue) return null;
        return new HexColor(red, green, blue);
    }

    public string ToHex() => $"#{R:X2}{G:X2}{B:X2}";

    public override string ToString() => ToHex();

    /// <summary>Relative luminance; below ~0.5 a color is dark enough to need light text.</summary>
    public double Luminance => 0.2126 * Red + 0.7152 * Green + 0.0722 * Blue;

    public bool IsDark => Luminance < 0.5;
}
