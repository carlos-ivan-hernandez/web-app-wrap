using System.Runtime.Versioning;
using WebAppWrap.Core.Icons;
using WebAppWrap.Core.Windows;

namespace WebAppWrap.Core;

/// <summary>Everything needed to create one wrapped app.</summary>
public sealed record AppSpec(AppLocation Location, Uri Url, IconSource Icon, HexColor TitleBarColor)
{
    public string Name => Location.Name;
    public string Id => InputNormalizer.AppId(Location.Name);
}

/// <summary>
/// Creates a wrapped app. On Windows a wrapped app is not a copy of the program: every app runs
/// the one installed WebAppWrap.exe (as Chrome's installed web apps run chrome.exe). What makes it
/// its own app is a Start menu shortcut that launches "WebAppWrap.exe --app &lt;id&gt;" with its own
/// icon and taskbar identity, plus a data folder with its settings, icon, and separate sign-ins.
/// </summary>
public static class AppBuilder
{
    /// <summary>The per-user Start menu "Programs" folder, the default home for app shortcuts.</summary>
    public static string StartMenuPrograms => Environment.GetFolderPath(Environment.SpecialFolder.Programs);

    /// <summary>
    /// WebAppWrap.exe, which runs every wrapped app. The generator and the command-line tool are
    /// installed next to it.
    /// </summary>
    public static string RuntimePath => Path.Combine(AppContext.BaseDirectory, "WebAppWrap.exe");

    /// <summary>Writes the app's settings and icon, then creates its shortcut(s). Returns the Start menu shortcut path.</summary>
    [SupportedOSPlatform("windows")]
    public static string Build(AppSpec spec, string shortcutRoot, bool desktopShortcut = false)
    {
        if (!File.Exists(RuntimePath))
            throw new FileNotFoundException($"WebAppWrap.exe wasn’t found next to this program ({AppContext.BaseDirectory}). Reinstall Web App Wrap.");

        var id = spec.Id;
        Directory.CreateDirectory(AppStore.DirectoryFor(id));
        IconRenderer.WriteIco(spec.Icon, AppStore.IconPath(id));
        AppStore.Save(new AppConfig
        {
            Id = id,
            Name = spec.Name,
            Url = spec.Url.AbsoluteUri,
            TitleBarColor = spec.TitleBarColor.ToHex(),
        });

        var shortcut = spec.Location.ShortcutPath(shortcutRoot);
        CreateShortcut(spec, shortcut);
        if (desktopShortcut)
        {
            var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            CreateShortcut(spec, Path.Combine(desktop, InputNormalizer.FileSafeName(spec.Name) + ".lnk"));
        }
        return shortcut;
    }

    [SupportedOSPlatform("windows")]
    private static void CreateShortcut(AppSpec spec, string path) =>
        ShellLink.Create(
            shortcutPath: path,
            targetPath: RuntimePath,
            arguments: $"--app {spec.Id}",
            iconPath: AppStore.IconPath(spec.Id),
            appUserModelId: spec.Id,
            workingDirectory: AppStore.DirectoryFor(spec.Id),
            description: $"{spec.Name} ({spec.Url.Host})");

    /// <summary>
    /// The same choices the window makes: automatic icon zoom times the entry's zoom, and the
    /// site's theme color unless a color is given.
    /// </summary>
    public static async Task<AppSpec> SpecForAsync(BatchEntry entry, CancellationToken cancellationToken = default)
    {
        IconSource icon = new IconSource.Generated(entry.Location.Name);
        if (entry.Image is not null)
        {
            var bitmap = IconRenderer.LoadImage(entry.Image) ?? throw new IOException($"Couldn’t read an image from {entry.Image}.");
            icon = new IconSource.Image(bitmap, IconRenderer.AutomaticZoom(bitmap) * entry.Zoom);
        }
        var color = entry.TitleBarColor
            ?? await ThemeColor.FetchAsync(entry.Url, cancellationToken)
            ?? HexColor.DefaultTitleBar;
        return new AppSpec(entry.Location, entry.Url, icon, color);
    }

    public sealed record BatchResult(BatchEntry Entry, string? Shortcut, Exception? Error);

    /// <summary>Builds every app in a batch, one at a time, carrying on past failures.</summary>
    [SupportedOSPlatform("windows")]
    public static async Task<IReadOnlyList<BatchResult>> BuildBatchAsync(
        IReadOnlyList<BatchEntry> entries,
        string shortcutRoot,
        bool desktopShortcuts = false,
        Action<int, BatchEntry>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var results = new List<BatchResult>();
        for (var i = 0; i < entries.Count; i++)
        {
            var entry = entries[i];
            progress?.Invoke(i, entry);
            try
            {
                var spec = await SpecForAsync(entry, cancellationToken);
                var shortcut = await Task.Run(() => Build(spec, shortcutRoot, desktopShortcuts), cancellationToken);
                results.Add(new BatchResult(entry, shortcut, null));
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                results.Add(new BatchResult(entry, null, exception));
            }
        }
        return results;
    }
}
