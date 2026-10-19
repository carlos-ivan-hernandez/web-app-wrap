using System.Globalization;
using System.Text;

namespace WebAppWrap.Core;

/// <summary>Turns loosely typed user input into the values a wrapped app needs.</summary>
public static class InputNormalizer
{
    /// <summary>
    /// Accepts "example.com", "https://example.com/app", "localhost:3000", etc. Returns null
    /// unless the result is an http(s) URL with a valid host.
    /// </summary>
    public static Uri? NormalizeUrl(string? raw)
    {
        var text = raw?.Trim() ?? "";
        if (text.Length == 0) return null;

        if (!text.Contains("://", StringComparison.Ordinal))
        {
            var lower = text.ToLowerInvariant();
            var isLocal = lower.StartsWith("localhost", StringComparison.Ordinal)
                || lower.StartsWith("127.0.0.1", StringComparison.Ordinal)
                || lower.StartsWith("0.0.0.0", StringComparison.Ordinal);
            text = (isLocal ? "http://" : "https://") + text;
        }

        if (!Uri.TryCreate(text, UriKind.Absolute, out var uri)) return null;
        if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) return null;
        if (string.IsNullOrEmpty(uri.Host) || uri.Host.Any(c => !(char.IsLetterOrDigit(c) || c is '-' or '.' or '_' or ':' or '[' or ']')))
            return null;
        return uri;
    }

    /// <summary>Lowercase ASCII slug: "My Cool App!" -> "my-cool-app". Never empty.</summary>
    public static string Slug(string name)
    {
        var folded = new StringBuilder();
        foreach (var c in name.Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) folded.Append(c);
        }

        var result = new StringBuilder();
        var pendingHyphen = false;
        foreach (var c in folded.ToString().ToLowerInvariant())
        {
            if (c is >= 'a' and <= 'z' or >= '0' and <= '9')
            {
                if (pendingHyphen && result.Length > 0) result.Append('-');
                result.Append(c);
                pendingHyphen = false;
            }
            else
            {
                pendingHyphen = true;
            }
        }
        return result.Length == 0 ? "app" : result.ToString();
    }

    /// <summary>
    /// Stable identifier for a wrapped app (also its Windows taskbar identity). Sign-ins and
    /// storage are keyed by it, so recreating an app with the same name keeps them.
    /// </summary>
    public static string AppId(string name) => "com.waw.app." + Slug(name);

    private static readonly char[] InvalidFileNameChars = ['\\', '/', ':', '*', '?', '"', '<', '>', '|'];

    private static readonly HashSet<string> ReservedNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    };

    /// <summary>A name that is safe as a Windows file or folder name.</summary>
    public static string FileSafeName(string name)
    {
        var cleaned = new string(name.Select(c => char.IsControl(c) || InvalidFileNameChars.Contains(c) ? '-' : c).ToArray());
        // Windows drops trailing dots and spaces, which would make names collide.
        cleaned = cleaned.Trim().TrimEnd('.', ' ').TrimStart('.');
        if (cleaned.Length == 0) return "App";
        return ReservedNames.Contains(cleaned) ? cleaned + "_" : cleaned;
    }
}
