using System.Text.Json;
using System.Text.Json.Serialization;

namespace WebAppWrap.Core;

/// <summary>What a wrapped app points at. Saved as app.json in the app's data folder.</summary>
public sealed record AppConfig
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public required string Url { get; init; }
    /// <summary>"#RRGGBB" background for the tab bar.</summary>
    public required string TitleBarColor { get; init; }

    [JsonIgnore]
    public Uri BaseUrl => InputNormalizer.NormalizeUrl(Url) ?? throw new InvalidOperationException($"Invalid URL in app settings: {Url}");

    [JsonIgnore]
    public HexColor TitleBar => HexColor.FromHex(TitleBarColor) ?? HexColor.DefaultTitleBar;
}

/// <summary>
/// Each wrapped app's files live in %LOCALAPPDATA%\Web App Wrap\Apps\&lt;app id&gt;:
/// app.json (settings), icon.ico, window.json (size and position) and WebView2\ (sign-ins and storage).
/// </summary>
public static class AppStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public static string Root { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Web App Wrap", "Apps");

    public static string DirectoryFor(string appId) => Path.Combine(Root, appId);
    public static string ConfigPath(string appId) => Path.Combine(DirectoryFor(appId), "app.json");
    public static string IconPath(string appId) => Path.Combine(DirectoryFor(appId), "icon.ico");
    public static string WindowStatePath(string appId) => Path.Combine(DirectoryFor(appId), "window.json");
    public static string WebViewDataPath(string appId) => Path.Combine(DirectoryFor(appId), "WebView2");

    public static AppConfig? Load(string appId)
    {
        try
        {
            return JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(ConfigPath(appId)), JsonOptions);
        }
        catch (Exception exception) when (exception is IOException or JsonException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public static void Save(AppConfig config)
    {
        Directory.CreateDirectory(DirectoryFor(config.Id));
        File.WriteAllText(ConfigPath(config.Id), JsonSerializer.Serialize(config, JsonOptions));
    }
}
