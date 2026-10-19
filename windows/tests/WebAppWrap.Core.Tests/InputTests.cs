using WebAppWrap.Core;

namespace WebAppWrap.Core.Tests;

public class InputNormalizerTests
{
    [Theory]
    [InlineData("example.com", "https://example.com/")]
    [InlineData("  app.example.com/dashboard ", "https://app.example.com/dashboard")]
    [InlineData("http://example.com", "http://example.com/")]
    [InlineData("localhost:3000", "http://localhost:3000/")]
    [InlineData("127.0.0.1:8080/x", "http://127.0.0.1:8080/x")]
    public void NormalizesUrls(string input, string expected) =>
        Assert.Equal(expected, InputNormalizer.NormalizeUrl(input)?.AbsoluteUri);

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("ftp://example.com")]
    [InlineData("not a url")]
    [InlineData("https://")]
    public void RejectsInvalidUrls(string input) => Assert.Null(InputNormalizer.NormalizeUrl(input));

    [Theory]
    [InlineData("My Cool App!", "my-cool-app")]
    [InlineData("  Café   Crème ", "cafe-creme")]
    [InlineData("🚀", "app")]
    [InlineData("A--B", "a-b")]
    public void Slugs(string input, string expected) => Assert.Equal(expected, InputNormalizer.Slug(input));

    [Fact]
    public void AppIdUsesWawPrefix() => Assert.Equal("com.waw.app.linear", InputNormalizer.AppId("Linear"));

    [Theory]
    [InlineData("A/B:C", "A-B-C")]
    [InlineData("What? <now>", "What- -now-")]
    [InlineData(".hidden", "hidden")]
    [InlineData("Trailing dots...", "Trailing dots")]
    [InlineData("CON", "CON_")]
    [InlineData("  ", "App")]
    public void FileSafeNames(string input, string expected) => Assert.Equal(expected, InputNormalizer.FileSafeName(input));
}

public class AppLocationTests
{
    private static readonly string Root = Path.Combine("Start", "Programs");

    [Fact]
    public void PlainName()
    {
        var location = new AppLocation("Photos");
        Assert.Equal("Photos", location.Name);
        Assert.Empty(location.Folders);
        Assert.Equal(Path.Combine(Root, "Photos.lnk"), location.ShortcutPath(Root));
    }

    [Theory]
    [InlineData("Web App Wrap/Photos")]
    [InlineData("Web App Wrap\\Photos")]
    public void Subfolder(string input)
    {
        var location = new AppLocation(input);
        Assert.Equal("Photos", location.Name);
        Assert.Equal(["Web App Wrap"], location.Folders);
        Assert.Equal(Path.Combine(Root, "Web App Wrap", "Photos.lnk"), location.ShortcutPath(Root));
        Assert.Equal("Web App Wrap › Photos", location.DisplayPath);
    }

    [Fact]
    public void IgnoresEmptyAndRelativeParts()
    {
        var location = new AppLocation(" /Web Wrap// ../ Photos ");
        Assert.Equal("Photos", location.Name);
        Assert.Equal(Path.Combine(Root, "Web Wrap", "Photos.lnk"), location.ShortcutPath(Root));
    }

    [Fact]
    public void Equality() => Assert.Equal(new AppLocation("A/B"), new AppLocation("A\\B"));
}

public class LinkPolicyTests
{
    private readonly LinkPolicy _policy = new(new Uri("https://app.example.com/home"));

    [Theory]
    [InlineData("https://app.example.com/settings", LinkDestination.App)]
    [InlineData("http://APP.example.com", LinkDestination.App)]
    [InlineData("https://www.app.example.com", LinkDestination.App)]
    [InlineData("https://eu.app.example.com/x", LinkDestination.App)]
    [InlineData("https://example.com", LinkDestination.Browser)]
    [InlineData("https://github.com/foo", LinkDestination.Browser)]
    [InlineData("https://notapp.example.com", LinkDestination.Browser)]
    [InlineData("https://app.example.com.evil.io", LinkDestination.Browser)]
    [InlineData("mailto:someone@example.com", LinkDestination.System)]
    [InlineData("tel:5551234", LinkDestination.System)]
    [InlineData("zoommtg://zoom.us/join", LinkDestination.System)]
    [InlineData("about:blank", LinkDestination.App)]
    [InlineData("blob:https://app.example.com/abc", LinkDestination.App)]
    public void Routes(string url, LinkDestination expected) => Assert.Equal(expected, _policy.DestinationFor(url));

    [Fact]
    public void WwwBase()
    {
        var policy = new LinkPolicy(new Uri("https://www.example.com"));
        Assert.Equal(LinkDestination.App, policy.DestinationFor("https://example.com/a"));
        Assert.Equal(LinkDestination.App, policy.DestinationFor("https://docs.example.com"));
    }
}
