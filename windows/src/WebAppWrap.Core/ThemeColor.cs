using System.Text.Json;
using System.Text.RegularExpressions;

namespace WebAppWrap.Core;

/// <summary>
/// Finds a site's theme color: &lt;meta name="theme-color"&gt; in its HTML, or theme_color in the
/// web app manifest the HTML links to (single-page apps often declare it only there).
/// </summary>
public static partial class ThemeColor
{
    private static readonly HttpClient Http = CreateHttpClient();

    /// <summary>Downloads the page (and its manifest if needed). Null if none is declared or the site can't be reached.</summary>
    public static async Task<HexColor?> FetchAsync(Uri url, CancellationToken cancellationToken = default)
    {
        try
        {
            using var response = await Http.GetAsync(url, cancellationToken);
            var html = await response.Content.ReadAsStringAsync(cancellationToken);
            if (FromHtml(html) is { } color) return color;

            if (ManifestUrl(html, response.RequestMessage?.RequestUri ?? url) is not { } manifestUrl) return null;
            var manifest = await Http.GetStringAsync(manifestUrl, cancellationToken);
            return FromManifest(manifest);
        }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException or InvalidOperationException)
        {
            return null;
        }
    }

    /// <summary>
    /// The content of the first theme-color meta tag. Tags without a media query win over
    /// light/dark variants, and a light variant wins over a dark one.
    /// </summary>
    public static HexColor? FromHtml(string html)
    {
        return Tags("meta", html)
            .Where(tag => tag.GetValueOrDefault("name")?.ToLowerInvariant() == "theme-color")
            .Select(tag =>
            {
                var media = tag.GetValueOrDefault("media")?.ToLowerInvariant() ?? "";
                var rank = media.Length == 0 ? 0 : media.Contains("dark") ? 2 : 1;
                return (Color: HexColor.FromCss(tag.GetValueOrDefault("content")), Rank: rank);
            })
            .Where(candidate => candidate.Color is not null)
            .OrderBy(candidate => candidate.Rank)
            .Select(candidate => candidate.Color)
            .FirstOrDefault();
    }

    /// <summary>The manifest linked from the HTML, resolved against the page's URL.</summary>
    public static Uri? ManifestUrl(string html, Uri pageUrl)
    {
        var link = Tags("link", html).FirstOrDefault(tag =>
            (tag.GetValueOrDefault("rel")?.ToLowerInvariant().Split(' ').Contains("manifest") ?? false)
            && tag.ContainsKey("href"));
        return link is not null && Uri.TryCreate(pageUrl, link["href"], out var resolved) ? resolved : null;
    }

    public static HexColor? FromManifest(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.ValueKind == JsonValueKind.Object
                && document.RootElement.TryGetProperty("theme_color", out var value)
                && value.ValueKind == JsonValueKind.String
                ? HexColor.FromCss(value.GetString())
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    // Minimal tag parsing: enough for <head> metadata, not a full HTML parser.

    [GeneratedRegex("""([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))""")]
    private static partial Regex AttributePattern();

    /// <summary>Attributes of every &lt;name ...&gt; tag, with lowercased attribute names.</summary>
    private static IEnumerable<Dictionary<string, string>> Tags(string name, string html)
    {
        var tagPattern = new Regex($@"<{name}\b[^>]*>", RegexOptions.IgnoreCase);
        foreach (Match tag in tagPattern.Matches(html))
        {
            var attributes = new Dictionary<string, string>();
            foreach (Match attribute in AttributePattern().Matches(tag.Value))
            {
                var key = attribute.Groups[1].Value.ToLowerInvariant();
                var value = attribute.Groups[2].Success ? attribute.Groups[2].Value
                    : attribute.Groups[3].Success ? attribute.Groups[3].Value
                    : attribute.Groups[4].Value;
                attributes.TryAdd(key, value);
            }
            yield return attributes;
        }
    }

    private static HttpClient CreateHttpClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0");
        return client;
    }
}
