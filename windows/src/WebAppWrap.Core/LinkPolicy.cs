namespace WebAppWrap.Core;

public enum LinkDestination
{
    /// <summary>Load inside the app.</summary>
    App,
    /// <summary>Open in the default web browser.</summary>
    Browser,
    /// <summary>Hand to whatever app handles the scheme (mailto:, tel:, zoommtg:, ...).</summary>
    System,
}

/// <summary>Decides whether a URL belongs to the wrapped web app or should go elsewhere.</summary>
public sealed class LinkPolicy(Uri baseUrl)
{
    private readonly string _baseHost = CanonicalHost(baseUrl.Host);

    public Uri BaseUrl { get; } = baseUrl;

    public LinkDestination DestinationFor(Uri url)
    {
        switch (url.Scheme.ToLowerInvariant())
        {
            case "about" or "blob" or "data" or "javascript":
                return LinkDestination.App;
            case "http" or "https":
                return IsInternalHost(url.Host) ? LinkDestination.App : LinkDestination.Browser;
            default:
                return LinkDestination.System;
        }
    }

    public LinkDestination DestinationFor(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) ? DestinationFor(uri) : LinkDestination.App;

    /// <summary>Same host as the base URL, or a subdomain of it. "www." is ignored on both sides.</summary>
    private bool IsInternalHost(string host)
    {
        if (string.IsNullOrEmpty(host)) return false;
        var candidate = CanonicalHost(host);
        return candidate == _baseHost || candidate.EndsWith("." + _baseHost, StringComparison.Ordinal);
    }

    private static string CanonicalHost(string host)
    {
        var lower = host.ToLowerInvariant();
        return lower.StartsWith("www.", StringComparison.Ordinal) ? lower[4..] : lower;
    }
}
