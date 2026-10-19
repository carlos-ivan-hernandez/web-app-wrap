using WebAppWrap.Core;

namespace WebAppWrap.Core.Tests;

public class HexColorTests
{
    [Theory]
    [InlineData("#1a1a1a", "#1A1A1A")]
    [InlineData("FF8000", "#FF8000")]
    [InlineData(" #fff ", "#FFFFFF")]
    public void ParsesHex(string input, string expected) => Assert.Equal(expected, HexColor.FromHex(input)?.ToHex());

    [Theory]
    [InlineData("")]
    [InlineData("#12345")]
    [InlineData("#GGGGGG")]
    public void RejectsInvalidHex(string input) => Assert.Null(HexColor.FromHex(input));

    [Theory]
    [InlineData("#1a1a1aff", "#1A1A1A")]
    [InlineData("#abcd", "#AABBCC")]
    [InlineData("rgb(26, 26, 26)", "#1A1A1A")]
    [InlineData("rgba(255,0,0,0.5)", "#FF0000")]
    [InlineData("rgb(100% 0% 0% / 50%)", "#FF0000")]
    [InlineData("White", "#FFFFFF")]
    public void ParsesCss(string input, string expected) => Assert.Equal(expected, HexColor.FromCss(input)?.ToHex());

    [Fact]
    public void RejectsUnsupportedCss() => Assert.Null(HexColor.FromCss("hsl(0, 0%, 10%)"));

    [Fact]
    public void Darkness()
    {
        Assert.True(HexColor.DefaultTitleBar.IsDark);
        Assert.False(HexColor.FromHex("#f2f2f2")!.Value.IsDark);
    }
}

public class ThemeColorTests
{
    [Fact]
    public void MultilineMetaTag()
    {
        const string html = """
            <head>
                <meta
                  name="theme-color"
                  content="#1a1a1a"
                />
            </head>
            """;
        Assert.Equal("#1A1A1A", ThemeColor.FromHtml(html)?.ToHex());
    }

    [Fact]
    public void AttributeOrderQuotesAndCase() =>
        Assert.Equal("#FFFFFF", ThemeColor.FromHtml("<META content='#FFF' NAME=theme-color>")?.ToHex());

    [Fact]
    public void PrefersTagWithoutMediaThenLight()
    {
        const string html = """
            <meta name="theme-color" media="(prefers-color-scheme: dark)" content="#000000">
            <meta name="theme-color" media="(prefers-color-scheme: light)" content="#eeeeee">
            """;
        Assert.Equal("#EEEEEE", ThemeColor.FromHtml(html)?.ToHex());
        Assert.Equal("#123456", ThemeColor.FromHtml(html + """<meta name="theme-color" content="#123456">""")?.ToHex());
    }

    [Fact]
    public void NoThemeColor()
    {
        Assert.Null(ThemeColor.FromHtml("""<meta name="description" content="#abcdef">"""));
        Assert.Null(ThemeColor.FromHtml("""<meta name="theme-color" content="var(--brand)">"""));
    }

    [Fact]
    public void ManifestLink()
    {
        var page = new Uri("https://kphotos.vercel.app/login");
        Assert.Equal(
            "https://kphotos.vercel.app/manifest.webmanifest",
            ThemeColor.ManifestUrl("""<link rel="icon" href="/icon.svg"><link rel="manifest" href="/manifest.webmanifest">""", page)?.AbsoluteUri);
        Assert.Null(ThemeColor.ManifestUrl("""<link rel="icon" href="/a.png">""", page));
    }

    [Fact]
    public void ManifestThemeColor()
    {
        Assert.Equal("#1A1A1A", ThemeColor.FromManifest("""{"name":"Photos","theme_color":"#1a1a1a"}""")?.ToHex());
        Assert.Null(ThemeColor.FromManifest("{}"));
        Assert.Null(ThemeColor.FromManifest("not json"));
    }
}

public class BatchFileTests
{
    private static readonly string Base = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "apps"));

    private static IReadOnlyList<BatchEntry> Parse(string json) => BatchFile.Parse(json, Base);

    private static string ErrorMessage(string json)
    {
        try
        {
            Parse(json);
            return "no error";
        }
        catch (BatchFileException exception)
        {
            return exception.Message;
        }
    }

    [Fact]
    public void FullEntry()
    {
        var entry = Assert.Single(Parse("""
            [{"name": "Web App Wrap/Photos", "url": "kphotos.vercel.app", "image": "icons/photos.png",
              "zoom": 1.5, "titleBarColor": "#1a1a1a"}]
            """));
        Assert.Equal(new AppLocation("Web App Wrap/Photos"), entry.Location);
        Assert.Equal("https://kphotos.vercel.app/", entry.Url.AbsoluteUri);
        Assert.Equal(Path.Combine(Base, "icons", "photos.png"), entry.Image);
        Assert.Equal(1.5, entry.Zoom);
        Assert.Equal("#1A1A1A", entry.TitleBarColor?.ToHex());
    }

    [Fact]
    public void MinimalEntryUsesDefaults()
    {
        var entry = Assert.Single(Parse("""[{"name": "Linear", "url": "linear.app"}]"""));
        Assert.Null(entry.Image);
        Assert.Equal(1, entry.Zoom);
        Assert.Null(entry.TitleBarColor);
    }

    [Fact]
    public void ParentRelativeImagePath()
    {
        var entry = Assert.Single(Parse("""[{"name": "B", "url": "b.com", "image": "../shared/b.png"}]"""));
        Assert.Equal(Path.GetFullPath(Path.Combine(Base, "..", "shared", "b.png")), entry.Image);
    }

    [Fact]
    public void RejectsNonArray()
    {
        Assert.Equal("The file must contain a JSON array of app objects.", ErrorMessage("""{"name": "A", "url": "a.com"}"""));
        Assert.Equal("The file isn’t valid JSON.", ErrorMessage("not json"));
        Assert.Equal("The array is empty.", ErrorMessage("[]"));
    }

    [Fact]
    public void ReportsEveryProblemAtOnce()
    {
        var message = ErrorMessage("""
            [{"name": "Good", "url": "good.com"},
             {"url": "nameless.com"},
             {"name": "Bad", "url": "not a url", "zoom": 9, "titleBarColor": "teal", "icon": "x.png"},
             "oops"]
            """);
        Assert.Contains("Entry 2: “name” is missing.", message);
        Assert.Contains("Entry 3 (Bad): unknown field “icon”", message);
        Assert.Contains("“url” is missing or isn’t a web address", message);
        Assert.Contains("“zoom” must be a number from 1 to 3", message);
        Assert.Contains("“titleBarColor” must be a color", message);
        Assert.Contains("Entry 4 isn’t an object.", message);
        Assert.DoesNotContain("Entry 1", message);
    }

    [Fact]
    public void RejectsDuplicateDestinations()
    {
        Assert.Contains("More than one entry would create photos.lnk",
            ErrorMessage("""[{"name": "Photos", "url": "a.com"}, {"name": "photos", "url": "b.com"}]"""));
        Assert.Equal("no error", ErrorMessage("""[{"name": "A/Photos", "url": "a.com"}, {"name": "B/Photos", "url": "b.com"}]"""));
    }
}
