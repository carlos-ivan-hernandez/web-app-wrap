using System.Text.Json;

namespace WebAppWrap.Core;

/// <summary>
/// One app in a batch file. The fields mirror the Web App Wrap window:
/// <code>
/// [
///   {
///     "name": "Web App Wrap/Photos",
///     "url": "https://kphotos.vercel.app",
///     "image": "icons\\photos.png",
///     "zoom": 1.2,
///     "titleBarColor": "#1a1a1a"
///   }
/// ]
/// </code>
/// Only name and url are required. name may include folders, as in the window. image is a path,
/// relative to the JSON file unless absolute (~ works). zoom (1–3) is on top of the automatic
/// zoom that crops off a border. titleBarColor defaults to the site's theme color.
/// </summary>
public sealed record BatchEntry(AppLocation Location, Uri Url, string? Image, double Zoom, HexColor? TitleBarColor);

public sealed class BatchFileException(string message) : Exception(message);

public static class BatchFile
{
    public const double MinZoom = 1, MaxZoom = 3;

    private static readonly HashSet<string> KnownFields = ["name", "url", "image", "zoom", "titleBarColor"];

    /// <summary>
    /// Reads every entry, or throws one exception listing every problem found (so a batch never
    /// half-runs because of a typo in its last entry).
    /// </summary>
    public static IReadOnlyList<BatchEntry> Parse(string json, string baseDirectory)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(json, new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip });
        }
        catch (JsonException)
        {
            throw new BatchFileException("The file isn’t valid JSON.");
        }

        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Array)
                throw new BatchFileException("The file must contain a JSON array of app objects.");
            if (root.GetArrayLength() == 0)
                throw new BatchFileException("The array is empty.");

            var entries = new List<BatchEntry>();
            var problems = new List<string>();
            var index = 0;

            foreach (var element in root.EnumerateArray())
            {
                index++;
                var label = $"Entry {index}";
                if (element.ValueKind != JsonValueKind.Object)
                {
                    problems.Add($"{label} isn’t an object.");
                    continue;
                }

                var name = StringField(element, "name");
                var entryLabel = name is null ? label : $"{label} ({name})";
                var entryProblems = new List<string>();

                var unknown = element.EnumerateObject().Select(p => p.Name).Where(n => !KnownFields.Contains(n)).Order().ToList();
                if (unknown.Count > 0)
                    entryProblems.Add($"unknown field{(unknown.Count == 1 ? "" : "s")} {string.Join(", ", unknown.Select(u => $"“{u}”"))}");

                var location = new AppLocation(name ?? "");
                if (location.Name.Length == 0) entryProblems.Add("“name” is missing");

                var url = InputNormalizer.NormalizeUrl(StringField(element, "url"));
                if (url is null) entryProblems.Add("“url” is missing or isn’t a web address");

                string? image = null;
                if (element.TryGetProperty("image", out var imageValue) && imageValue.ValueKind != JsonValueKind.Null)
                {
                    var path = imageValue.ValueKind == JsonValueKind.String ? imageValue.GetString()?.Trim() : null;
                    if (string.IsNullOrEmpty(path)) entryProblems.Add("“image” must be a file path");
                    else image = ResolvePath(path, baseDirectory);
                }

                var zoom = 1.0;
                if (element.TryGetProperty("zoom", out var zoomValue) && zoomValue.ValueKind != JsonValueKind.Null)
                {
                    if (zoomValue.ValueKind == JsonValueKind.Number && zoomValue.GetDouble() is var number and >= MinZoom and <= MaxZoom)
                        zoom = number;
                    else
                        entryProblems.Add("“zoom” must be a number from 1 to 3");
                }

                HexColor? titleBarColor = null;
                if (element.TryGetProperty("titleBarColor", out var colorValue) && colorValue.ValueKind != JsonValueKind.Null)
                {
                    titleBarColor = colorValue.ValueKind == JsonValueKind.String ? HexColor.FromCss(colorValue.GetString()) : null;
                    if (titleBarColor is null) entryProblems.Add("“titleBarColor” must be a color like \"#1a1a1a\"");
                }

                if (url is not null && entryProblems.Count == 0)
                    entries.Add(new BatchEntry(location, url, image, zoom, titleBarColor));
                else
                    problems.Add($"{entryLabel}: {string.Join("; ", entryProblems)}.");
            }

            var duplicates = entries
                .GroupBy(e => e.Location.ShortcutPath("").ToLowerInvariant().Replace('\\', '/'))
                .Where(group => group.Count() > 1)
                .Select(group => group.Key)
                .Order();
            foreach (var duplicate in duplicates)
                problems.Add($"More than one entry would create {duplicate}.");

            if (problems.Count > 0) throw new BatchFileException(string.Join("\n", problems));
            return entries;
        }
    }

    private static string? StringField(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static string ResolvePath(string path, string baseDirectory)
    {
        if (path == "~" || path.StartsWith("~/", StringComparison.Ordinal) || path.StartsWith("~\\", StringComparison.Ordinal))
            path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), path.Length > 2 ? path[2..] : "");
        return Path.GetFullPath(Path.IsPathRooted(path) ? path : Path.Combine(baseDirectory, path));
    }
}
