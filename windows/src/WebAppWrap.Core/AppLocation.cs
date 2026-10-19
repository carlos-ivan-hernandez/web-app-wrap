namespace WebAppWrap.Core;

/// <summary>
/// The app name field accepts a path: "Web App Wrap/Photos" names the app "Photos" and puts its
/// shortcut in a "Web App Wrap" folder of the Start menu. "\" works as a separator too.
/// </summary>
public sealed record AppLocation
{
    public IReadOnlyList<string> Folders { get; }
    public string Name { get; }

    public AppLocation(string input)
    {
        var parts = input
            .Split('/', '\\')
            .Select(part => part.Trim())
            .Where(part => part.Length > 0 && part != "." && part != "..")
            .ToList();
        Name = parts.LastOrDefault() ?? "";
        Folders = parts.Take(Math.Max(0, parts.Count - 1)).Select(InputNormalizer.FileSafeName).ToList();
    }

    /// <summary>Where the app's shortcut goes, under <paramref name="root"/> (normally Start menu\Programs).</summary>
    public string ShortcutPath(string root) =>
        Path.Combine([root, .. Folders, InputNormalizer.FileSafeName(Name) + ".lnk"]);

    /// <summary>"Web App Wrap › Photos", for showing the destination in the UI.</summary>
    public string DisplayPath => string.Join(" › ", [.. Folders, InputNormalizer.FileSafeName(Name)]);

    public bool Equals(AppLocation? other) =>
        other is not null && Name == other.Name && Folders.SequenceEqual(other.Folders);

    public override int GetHashCode() => HashCode.Combine(Name, string.Join("/", Folders));
}
