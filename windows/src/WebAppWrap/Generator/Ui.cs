using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;

namespace WebAppWrap.Generator;

/// <summary>Small helpers for building the UI in code.</summary>
internal static class Ui
{
    public static readonly FontFamily Monospace = new("Cascadia Mono, Consolas");

    public static TextBlock Label(string text) =>
        new() { Text = text, Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"] };

    public static TextBlock Caption(string text = "") => new()
    {
        Text = text,
        Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
        Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        TextWrapping = TextWrapping.Wrap,
    };

    public static StackPanel Stack(double spacing, params UIElement[] children)
    {
        var stack = new StackPanel { Spacing = spacing };
        foreach (var child in children) stack.Children.Add(child);
        return stack;
    }

    public static StackPanel Row(double spacing, params UIElement[] children)
    {
        var stack = Stack(spacing, children);
        stack.Orientation = Orientation.Horizontal;
        return stack;
    }

    public static FontIcon Icon(string glyph, double size = 14) => new() { Glyph = glyph, FontSize = size };

    /// <summary>Wrapping text where **bold** and `code` spans are formatted.</summary>
    public static TextBlock Paragraph(string text, double lineHeight = 22)
    {
        var block = new TextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, LineHeight = lineHeight };
        var bold = false;
        var code = false;
        var current = "";

        void Flush()
        {
            if (current.Length == 0) return;
            var run = new Run { Text = current };
            if (bold) run.FontWeight = FontWeights.SemiBold;
            if (code) run.FontFamily = Monospace;
            block.Inlines.Add(run);
            current = "";
        }

        for (var i = 0; i < text.Length; i++)
        {
            if (text[i] == '*' && i + 1 < text.Length && text[i + 1] == '*')
            {
                Flush();
                bold = !bold;
                i++;
            }
            else if (text[i] == '`')
            {
                Flush();
                code = !code;
            }
            else
            {
                current += text[i];
            }
        }
        Flush();
        return block;
    }

    /// <summary>A shaded, selectable block of monospaced text.</summary>
    public static Border CodeBlock(string text) => new()
    {
        Background = (Brush)Application.Current.Resources["SubtleFillColorSecondaryBrush"],
        CornerRadius = new CornerRadius(6),
        Padding = new Thickness(14, 12, 14, 12),
        Child = new TextBlock
        {
            Text = text,
            FontFamily = Monospace,
            FontSize = 13,
            LineHeight = 20,
            TextWrapping = TextWrapping.Wrap,
            IsTextSelectionEnabled = true,
        },
    };

    /// <summary>Bullet list with the same **bold** / `code` formatting as Paragraph.</summary>
    public static StackPanel Bullets(params string[] items)
    {
        var list = new StackPanel { Spacing = 10 };
        foreach (var item in items)
        {
            var row = new Grid { ColumnSpacing = 10 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.Children.Add(new TextBlock { Text = "•", Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"] });
            var text = Paragraph(item);
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            list.Children.Add(row);
        }
        return list;
    }
}
