using SkiaSharp;

namespace WebAppWrap.Core.Icons;

/// <summary>What an icon is drawn from.</summary>
public abstract record IconSource
{
    /// <summary>A gradient tile (hue derived from the name) showing the name's first letter.</summary>
    public sealed record Generated(string Name) : IconSource;

    /// <summary>
    /// A user image, cropped to fill the rounded-square tile. Zoom 1 shows the whole image;
    /// larger values crop in, keeping it centered.
    /// </summary>
    public sealed record Image(SKBitmap Bitmap, double Zoom) : IconSource;

    /// <summary>How far the user can zoom in, on top of the automatic zoom that crops off a border.</summary>
    public const double MinUserZoom = 1, MaxUserZoom = 3;

    /// <summary>The furthest the automatic zoom will go looking for the edge of the artwork.</summary>
    public const double MaxAutomaticZoom = 3;
}

/// <summary>
/// Draws app icons: a rounded square filling most of the canvas, in the style of Windows 11 app
/// icons, and writes them as multi-size .ico files.
/// </summary>
public static class IconRenderer
{
    private const float Canvas = 1024;
    // A small margin and soft corners, like Windows 11's own app icons.
    private static readonly SKRect TileRect = new(48, 48, Canvas - 48, Canvas - 48);
    private const float CornerRadius = 0.18f * (Canvas - 96);

    /// <summary>Every size Windows picks from for shortcuts, the taskbar, Start, and Explorer views.</summary>
    public static readonly int[] IcoSizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256];

    // ---- Output ----

    public static SKBitmap Render(IconSource source, int pixels)
    {
        var bitmap = new SKBitmap(new SKImageInfo(pixels, pixels, SKColorType.Rgba8888, SKAlphaType.Premul));
        using var canvas = new SKCanvas(bitmap);
        canvas.Clear(SKColors.Transparent);
        canvas.Scale(pixels / Canvas);
        Draw(source, canvas);
        canvas.Flush();
        return bitmap;
    }

    public static byte[] RenderPng(IconSource source, int pixels)
    {
        using var bitmap = Render(source, pixels);
        using var data = bitmap.Encode(SKEncodedImageFormat.Png, 100);
        return data.ToArray();
    }

    public static byte[] RenderIco(IconSource source) =>
        IcoWriter.Write(IcoSizes.Select(size => (size, RenderPng(source, size))).ToList());

    public static void WriteIco(IconSource source, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        File.WriteAllBytes(path, RenderIco(source));
    }

    /// <summary>Loads PNG, JPEG, BMP, GIF, WebP or ICO (the largest frame). Null if unreadable.</summary>
    public static SKBitmap? LoadImage(string path)
    {
        try
        {
            if (Path.GetExtension(path).Equals(".ico", StringComparison.OrdinalIgnoreCase)
                && IcoWriter.LargestFrame(File.ReadAllBytes(path)) is { } frame)
                return SKBitmap.Decode(frame);
            return SKBitmap.Decode(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return null;
        }
    }

    // ---- Automatic zoom ----

    /// <summary>
    /// The smallest zoom at which the tile shows only the image's artwork, not its background.
    /// The background is whatever the four corners share: transparency, or one solid color such as
    /// a white border around an already-rounded icon. Returns 1 for images with no shared corner
    /// color, or when no zoom up to the maximum gets clear of it (e.g. a small logo on a white page),
    /// since cropping wouldn't help there.
    /// </summary>
    public static double AutomaticZoom(SKBitmap image)
    {
        // Analyze at up to 1024 px on the long side.
        var factor = Math.Min(1.0, 1024.0 / Math.Max(1, Math.Max(image.Width, image.Height)));
        var width = Math.Max(1, (int)(image.Width * factor));
        var height = Math.Max(1, (int)(image.Height * factor));
        using var pixels = image.Resize(new SKImageInfo(width, height, SKColorType.Rgba8888, SKAlphaType.Unpremul), new SKSamplingOptions(SKFilterMode.Linear))
            ?? image.Copy(SKColorType.Rgba8888);
        if (pixels is null) return 1;
        width = pixels.Width;
        height = pixels.Height;

        static int Distance(SKColor p, SKColor q) =>
            Math.Max(Math.Max(Math.Abs(p.Red - q.Red), Math.Abs(p.Green - q.Green)), Math.Max(Math.Abs(p.Blue - q.Blue), Math.Abs(p.Alpha - q.Alpha)));

        SKColor[] corners = [pixels.GetPixel(0, 0), pixels.GetPixel(width - 1, 0), pixels.GetPixel(0, height - 1), pixels.GetPixel(width - 1, height - 1)];
        var corner = corners[0];
        var cornerIsTransparent = corners.All(c => c.Alpha < 128);
        if (!cornerIsTransparent && !corners.All(c => Distance(c, corner) <= 24)) return 1;

        // Anything within ~40% of the corner color counts as border, which also catches the
        // anti-aliased ring and any soft shadow where the border meets the artwork.
        bool IsBackground(int x, int y)
        {
            var pixel = pixels.GetPixel(x, y);
            return pixel.Alpha < 128 || (!cornerIsTransparent && Distance(pixel, corner) < 100);
        }

        // The tile is aspect-filled, so at zoom 1 it spans half the shorter side around the center.
        double centerX = width / 2.0, centerY = height / 2.0, halfExtent = Math.Min(width, height) / 2.0;
        var outline = TileOutline(1.0).Concat(TileOutline(1.02)).ToList();

        bool IsClear(double zoom)
        {
            var reach = halfExtent / zoom;
            foreach (var (u, v) in outline)
            {
                var x = Math.Clamp((int)(centerX + u * reach), 0, width - 1);
                var y = Math.Clamp((int)(centerY - v * reach), 0, height - 1);
                if (IsBackground(x, y)) return false;
            }
            return true;
        }

        const double maximum = IconSource.MaxAutomaticZoom;
        if (IsClear(1)) return 1;
        if (!IsClear(maximum)) return 1;
        double low = 1, high = maximum;
        for (var i = 0; i < 20; i++)
        {
            var middle = (low + high) / 2;
            if (IsClear(middle)) high = middle; else low = middle;
        }
        // A little extra so no faint line survives at small icon sizes.
        return Math.Min(maximum, high * 1.02);
    }

    /// <summary>Points on the tile's rounded-square outline, as offsets in [-scale, scale] around its center.</summary>
    private static IEnumerable<(double U, double V)> TileOutline(double scale)
    {
        var radius = CornerRadius / (TileRect.Width / 2);  // in unit offsets
        var straight = 1 - radius;
        const int stepsPerEdge = 120, stepsPerCorner = 60;
        for (var i = 0; i <= stepsPerEdge; i++)
        {
            var t = -straight + 2 * straight * i / stepsPerEdge;
            yield return (t * scale, 1 * scale);
            yield return (t * scale, -1 * scale);
            yield return (1 * scale, t * scale);
            yield return (-1 * scale, t * scale);
        }
        foreach (var (cx, cy) in new[] { (straight, straight), (-straight, straight), (-straight, -straight), (straight, -straight) })
        {
            for (var i = 0; i <= stepsPerCorner; i++)
            {
                var angle = Math.PI / 2 * i / stepsPerCorner;
                var u = cx + Math.Sign(cx) * radius * Math.Cos(angle);
                var v = cy + Math.Sign(cy) * radius * Math.Sin(angle);
                yield return (u * scale, v * scale);
            }
        }
    }

    // ---- Drawing (in 1024-unit canvas coordinates) ----

    private static void Draw(IconSource source, SKCanvas canvas)
    {
        using var shape = new SKPath();
        shape.AddRoundRect(TileRect, CornerRadius, CornerRadius);

        canvas.Save();
        canvas.ClipPath(shape, antialias: true);
        switch (source)
        {
            case IconSource.Generated generated:
                DrawGradient(generated.Name, canvas);
                DrawLetter(generated.Name, canvas);
                break;

            case IconSource.Image image:
                using (var white = new SKPaint { Color = SKColors.White })
                    canvas.DrawRect(TileRect, white);
                var zoom = Math.Max(1, image.Zoom);
                var grow = (float)(TileRect.Width * (zoom - 1) / 2);
                var target = TileRect;
                target.Inflate(grow, grow);
                DrawAspectFill(image.Bitmap, target, canvas);
                break;
        }
        canvas.Restore();
    }

    private static void DrawGradient(string seed, SKCanvas canvas)
    {
        // djb2: stable across runs and platforms.
        ulong hash = 5381;
        foreach (var b in System.Text.Encoding.UTF8.GetBytes(seed.ToLowerInvariant())) hash = hash * 33 + b;
        var hue = (float)(hash % 360);

        var top = SKColor.FromHsv(hue, 55, 98);
        var bottom = SKColor.FromHsv((hue + 21.6f) % 360, 80, 74);
        using var paint = new SKPaint
        {
            Shader = SKShader.CreateLinearGradient(
                new SKPoint(TileRect.MidX, TileRect.Top), new SKPoint(TileRect.MidX, TileRect.Bottom),
                [top, bottom], SKShaderTileMode.Clamp),
        };
        canvas.DrawRect(TileRect, paint);
    }

    private static void DrawLetter(string name, SKCanvas canvas)
    {
        var trimmed = name.Trim();
        var letter = trimmed.Length == 0 ? "?" : char.ConvertFromUtf32(char.ConvertToUtf32(trimmed, 0)).ToUpperInvariant();

        var typeface = SKTypeface.FromFamilyName("Segoe UI Variable Display", SKFontStyle.Bold)
            ?? SKTypeface.FromFamilyName("Segoe UI", SKFontStyle.Bold)
            ?? SKTypeface.Default;
        using var font = new SKFont(typeface, 520) { Subpixel = true, Edging = SKFontEdging.Antialias };
        using var paint = new SKPaint { Color = SKColors.White, IsAntialias = true };

        var width = font.MeasureText(letter);
        var capHeight = font.Metrics.CapHeight > 0 ? font.Metrics.CapHeight : 520 * 0.7f;
        var baseline = TileRect.MidY + capHeight / 2;
        canvas.DrawText(letter, TileRect.MidX - width / 2, baseline, SKTextAlign.Left, font, paint);
    }

    private static void DrawAspectFill(SKBitmap image, SKRect rect, SKCanvas canvas)
    {
        if (image.Width <= 0 || image.Height <= 0) return;
        var ratio = Math.Max(rect.Width / image.Width, rect.Height / image.Height);
        var drawnWidth = image.Width * ratio;
        var drawnHeight = image.Height * ratio;
        var target = SKRect.Create(rect.MidX - drawnWidth / 2, rect.MidY - drawnHeight / 2, drawnWidth, drawnHeight);
        using var skImage = SKImage.FromBitmap(image);
        using var paint = new SKPaint { IsAntialias = true };
        canvas.DrawImage(skImage, target, new SKSamplingOptions(SKCubicResampler.Mitchell), paint);
    }
}
