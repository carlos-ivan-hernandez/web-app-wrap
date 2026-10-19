using SkiaSharp;
using WebAppWrap.Core.Icons;

namespace WebAppWrap.Core.Tests;

public class IconTests
{
    /// <summary>A dark rounded square on a white border, with a soft shadow: like an icon that's already rounded.</summary>
    private static SKBitmap BorderedIcon(float inset, float radius, int size = 1024)
    {
        var bitmap = new SKBitmap(size, size);
        using var canvas = new SKCanvas(bitmap);
        canvas.Clear(SKColors.White);
        var rect = new SKRect(size * inset, size * inset, size * (1 - inset), size * (1 - inset));
        using (var shadow = new SKPaint { Color = new SKColor(0, 0, 0, 90), IsAntialias = true, MaskFilter = SKMaskFilter.CreateBlur(SKBlurStyle.Normal, 12) })
            canvas.DrawRoundRect(SKRect.Create(rect.Left, rect.Top + 8, rect.Width, rect.Height), size * radius, size * radius, shadow);
        using (var paint = new SKPaint { Color = new SKColor(26, 26, 26), IsAntialias = true })
            canvas.DrawRoundRect(rect, size * radius, size * radius, paint);
        return bitmap;
    }

    [Theory]
    [InlineData(0.06f, 0.24f)]
    [InlineData(0.0f, 0.22f)]
    [InlineData(0.10f, 0.18f)]
    [InlineData(0.03f, 0.30f)]
    public void AutomaticZoomCropsOffBorder(float inset, float radius)
    {
        using var source = BorderedIcon(inset, radius);
        var zoom = IconRenderer.AutomaticZoom(source);
        Assert.InRange(zoom, 1, IconSource.MaxAutomaticZoom);

        // Every pixel well inside the rendered tile must be the dark artwork, never white or gray.
        using var icon = IconRenderer.Render(new IconSource.Image(source, zoom), 256);
        var lightest = 0;
        for (var y = 0; y < 256; y++)
        for (var x = 0; x < 256; x++)
        {
            var pixel = icon.GetPixel(x, y);
            if (pixel.Alpha == 255) lightest = Math.Max(lightest, Math.Max(pixel.Red, Math.Max(pixel.Green, pixel.Blue)));
        }
        Assert.True(lightest <= 40, $"zoom {zoom:F3} left a light pixel ({lightest}) inside the icon");
    }

    [Fact]
    public void FullBleedImageNeedsNoZoom()
    {
        using var photo = new SKBitmap(400, 300);
        using (var canvas = new SKCanvas(photo))
        using (var paint = new SKPaint { Shader = SKShader.CreateLinearGradient(new SKPoint(0, 0), new SKPoint(400, 300), [SKColors.Red, SKColors.Blue], SKShaderTileMode.Clamp) })
            canvas.DrawRect(0, 0, 400, 300, paint);
        Assert.Equal(1, IconRenderer.AutomaticZoom(photo));
    }

    [Fact]
    public void SmallLogoOnWhitePageIsLeftAlone()
    {
        using var page = new SKBitmap(1000, 1000);
        using (var canvas = new SKCanvas(page))
        {
            canvas.Clear(SKColors.White);
            using var paint = new SKPaint { Color = SKColors.Black };
            canvas.DrawCircle(500, 500, 60, paint);
        }
        Assert.Equal(1, IconRenderer.AutomaticZoom(page));
    }

    [Fact]
    public void GeneratedIconHasRoundedTransparentCorners()
    {
        using var icon = IconRenderer.Render(new IconSource.Generated("Photos"), 256);
        Assert.Equal(0, icon.GetPixel(0, 0).Alpha);
        Assert.Equal(0, icon.GetPixel(255, 255).Alpha);
        Assert.Equal(255, icon.GetPixel(128, 40).Alpha);
    }

    [Fact]
    public void IcoContainsEverySizeAsPng()
    {
        var ico = IconRenderer.RenderIco(new IconSource.Generated("Linear"));
        Assert.Equal(0, BitConverter.ToUInt16(ico, 0));
        Assert.Equal(1, BitConverter.ToUInt16(ico, 2));
        Assert.Equal(IconRenderer.IcoSizes.Length, BitConverter.ToUInt16(ico, 4));

        for (var i = 0; i < IconRenderer.IcoSizes.Length; i++)
        {
            var entry = 6 + 16 * i;
            var expected = IconRenderer.IcoSizes[i];
            Assert.Equal(expected >= 256 ? 0 : expected, ico[entry]);
            var length = BitConverter.ToInt32(ico, entry + 8);
            var offset = BitConverter.ToInt32(ico, entry + 12);
            using var frame = SKBitmap.Decode(ico[offset..(offset + length)]);
            Assert.Equal(expected, frame.Width);
            Assert.Equal(expected, frame.Height);
        }

        using var largest = SKBitmap.Decode(IcoWriter.LargestFrame(ico));
        Assert.Equal(256, largest.Width);
    }
}
