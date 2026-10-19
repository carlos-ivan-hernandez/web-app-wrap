using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using WebAppWrap.Core;
using Color = Windows.UI.Color;

namespace WebAppWrap.Browser;

/// <summary>Colors for the title bar and tabs, from the color chosen in Web App Wrap.</summary>
internal sealed class TitleBarPalette(HexColor color)
{
    public Color Background { get; } = Color.FromArgb(255, color.R, color.G, color.B);
    public Color Foreground { get; } = color.IsDark ? Color.FromArgb(255, 255, 255, 255) : Color.FromArgb(255, 0, 0, 0);
    public ElementTheme Theme { get; } = color.IsDark ? ElementTheme.Dark : ElementTheme.Light;

    public Color ForegroundWithAlpha(double alpha) =>
        Color.FromArgb((byte)Math.Round(alpha * 255), Foreground.R, Foreground.G, Foreground.B);

    public SolidColorBrush Brush(Color color) => new(color);

    /// <summary>
    /// TabView's lightweight-styling keys, so every tab has the bar's color (selected or not), thin
    /// dividers separate them, and only brighter text marks the selected tab.
    /// </summary>
    public void ApplyTo(ResourceDictionary resources)
    {
        var background = Brush(Background);
        var transparent = Brush(Color.FromArgb(0, 0, 0, 0));
        var text = Brush(ForegroundWithAlpha(0.95));
        var dimText = Brush(ForegroundWithAlpha(0.55));
        var hover = Brush(ForegroundWithAlpha(0.08));
        var pressed = Brush(ForegroundWithAlpha(0.14));

        resources["TabViewBackground"] = transparent;
        resources["TabViewBorderBrush"] = transparent;
        resources["TabViewSelectedItemBorderBrush"] = transparent;
        resources["TabViewItemSeparator"] = Brush(ForegroundWithAlpha(0.15));

        foreach (var state in new[] { "", "Selected", "PointerOver", "Pressed" })
            resources[$"TabViewItemHeaderBackground{state}"] = background;

        resources["TabViewItemHeaderForeground"] = dimText;
        resources["TabViewItemHeaderForegroundSelected"] = text;
        resources["TabViewItemHeaderForegroundPointerOver"] = text;
        resources["TabViewItemHeaderForegroundPressed"] = text;

        resources["TabViewItemHeaderCloseButtonForeground"] = dimText;
        resources["TabViewItemHeaderSelectedCloseButtonForeground"] = text;
        resources["TabViewItemHeaderCloseButtonForegroundPointerOver"] = text;
        resources["TabViewItemHeaderCloseButtonForegroundPressed"] = text;
        resources["TabViewItemHeaderCloseButtonBackground"] = transparent;
        resources["TabViewItemHeaderCloseButtonBackgroundPointerOver"] = hover;
        resources["TabViewItemHeaderCloseButtonBackgroundPressed"] = pressed;

        resources["TabViewButtonForeground"] = dimText;
        resources["TabViewButtonForegroundPointerOver"] = text;
        resources["TabViewButtonForegroundPressed"] = text;
        resources["TabViewButtonBackground"] = transparent;
        resources["TabViewButtonBackgroundPointerOver"] = hover;
        resources["TabViewButtonBackgroundPressed"] = pressed;

        // Tabs up to 240 wide, shrinking to fit when there are many.
        resources["TabViewItemMaxWidth"] = 240.0;
        resources["TabViewItemMinWidth"] = 72.0;
    }
}
