using WebAppWrap.Core;
using WebAppWrap.Core.Icons;

namespace WebAppWrap.Cli;

/// <summary>The same features as the Web App Wrap window, for scripts and automation.</summary>
public static class Program
{
    private const string Usage = """
        Usage:
          waw build --name <name> --url <address> [--image <file>] [--zoom <1-3>]
                    [--title-bar-color <#RRGGBB>] [--desktop] [--out <folder>]
              Create one app. <name> may include Start menu folders, e.g. "Web App Wrap/Photos".
              --zoom adds to the automatic zoom that crops off an image's border.
              The title bar color defaults to the site's theme color.
              --desktop also puts a shortcut on the desktop.
              --out is the folder for the shortcut (default: the Start menu).

          waw batch <file.json> [--desktop] [--out <folder>]
              Create every app listed in a JSON array of objects with the fields
              name, url, image, zoom and titleBarColor (only name and url are required).

          waw icon --name <name> [--image <file>] [--zoom <1-3>] --out <file.ico>
              Write just the icon.
        """;

    private sealed class UsageException(string message) : Exception(message + "\n\n" + Usage);

    public static async Task<int> Main(string[] args)
    {
        if (args.Length == 0 || args[0] is "help" or "--help" or "-h" or "/?")
        {
            Console.WriteLine(Usage);
            return 0;
        }

        var options = args[1..];
        try
        {
            switch (args[0])
            {
                case "build": await BuildAsync(options); return 0;
                case "batch": return await BatchAsync(options);
                case "icon": Icon(options); return 0;
                default: throw new UsageException($"Unknown command “{args[0]}”.");
            }
        }
        catch (Exception exception) when (exception is UsageException or BatchFileException or IOException or UnauthorizedAccessException or PlatformNotSupportedException)
        {
            Console.Error.WriteLine($"error: {exception.Message}");
            return 1;
        }
    }

    private static string? Value(string[] options, string flag)
    {
        var index = Array.IndexOf(options, flag);
        return index >= 0 && index + 1 < options.Length ? options[index + 1] : null;
    }

    private static bool Flag(string[] options, string flag) => options.Contains(flag);

    private static string ExpandPath(string path) =>
        Path.GetFullPath(Environment.ExpandEnvironmentVariables(
            path == "~" || path.StartsWith("~/") || path.StartsWith("~\\")
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), path.Length > 2 ? path[2..] : "")
                : path));

    private static IconSource IconFor(string name, string[] options)
    {
        if (Value(options, "--image") is not { } imagePath) return new IconSource.Generated(name);
        var image = IconRenderer.LoadImage(ExpandPath(imagePath)) ?? throw new UsageException($"Couldn’t read an image from {imagePath}.");
        var zoom = double.TryParse(Value(options, "--zoom"), System.Globalization.CultureInfo.InvariantCulture, out var extra) ? extra : 1;
        // --zoom is on top of the automatic zoom that crops off any border.
        return new IconSource.Image(image, IconRenderer.AutomaticZoom(image) * Math.Clamp(zoom, IconSource.MinUserZoom, IconSource.MaxUserZoom));
    }

    private static string ShortcutRoot(string[] options) =>
        Value(options, "--out") is { } folder ? ExpandPath(folder) : AppBuilder.StartMenuPrograms;

    private static void RequireWindows()
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Creating apps requires Windows.");
    }

    private static async Task BuildAsync(string[] options)
    {
        RequireWindows();
        var location = new AppLocation(Value(options, "--name") ?? "");
        if (location.Name.Length == 0) throw new UsageException("--name is required.");
        if (InputNormalizer.NormalizeUrl(Value(options, "--url")) is not { } url)
            throw new UsageException("--url is required and must be a web address.");

        HexColor color;
        if (Value(options, "--title-bar-color") is { } raw)
            color = HexColor.FromCss(raw) ?? throw new UsageException("--title-bar-color must look like #1E1E1E.");
        else
            color = await ThemeColor.FetchAsync(url) ?? HexColor.DefaultTitleBar;   // like the window: the site's theme color

        var spec = new AppSpec(location, url, IconFor(location.Name, options), color);
        if (OperatingSystem.IsWindows())
            Console.WriteLine(AppBuilder.Build(spec, ShortcutRoot(options), Flag(options, "--desktop")));
    }

    /// <summary>Returns 1 if any app failed, after building all the others.</summary>
    private static async Task<int> BatchAsync(string[] options)
    {
        RequireWindows();
        if (options.Length == 0 || options[0].StartsWith("--")) throw new UsageException("batch needs the path of a JSON file.");
        var file = ExpandPath(options[0]);
        var entries = BatchFile.Parse(await File.ReadAllTextAsync(file), Path.GetDirectoryName(file)!);
        var root = ShortcutRoot(options);
        if (!OperatingSystem.IsWindows()) return 1;

        var results = await AppBuilder.BuildBatchAsync(entries, root, Flag(options, "--desktop"),
            (index, entry) => Console.WriteLine($"[{index + 1}/{entries.Count}] {entry.Location.Name}…"));

        var failures = 0;
        foreach (var result in results)
        {
            if (result.Error is null)
            {
                Console.WriteLine($"✓ {result.Shortcut}");
            }
            else
            {
                failures++;
                Console.WriteLine($"✗ {result.Entry.Location.Name}: {result.Error.Message}");
            }
        }
        Console.WriteLine($"{results.Count - failures} of {results.Count} apps created.");
        return failures == 0 ? 0 : 1;
    }

    private static void Icon(string[] options)
    {
        var output = Value(options, "--out") ?? throw new UsageException("--out is required.");
        var path = ExpandPath(output);
        IconRenderer.WriteIco(IconFor(Value(options, "--name") ?? "App", options), path);
        Console.WriteLine(path);
    }
}
