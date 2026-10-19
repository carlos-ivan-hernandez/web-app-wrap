using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using WebAppWrap.Core;

namespace WebAppWrap.Generator;

/// <summary>What the tool is for, the window vs. the command line, and the command-line reference.</summary>
internal sealed class HelpWindow : Window
{
    public static readonly Uri RepositoryUrl = new("https://github.com/carlos-ivan-hernandez/web-app-wrap");

    public HelpWindow()
    {
        Title = "Web App Wrap Help";
        SystemBackdrop = new MicaBackdrop();
        var icon = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
        if (File.Exists(icon)) AppWindow.SetIcon(icon);
        var scale = NativeMethods.GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96.0;
        AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(760 * scale), (int)(820 * scale)));

        // The content stretches with the window, so text rewraps as the window is resized.
        var content = Ui.Stack(40,
            Header(),
            Section("What it’s for",
                Ui.Paragraph("Web App Wrap creates a separate Windows app for a website. Each app has its own Start menu entry, taskbar button and icon, its own window, and its own sign-ins and storage, so a web app you use every day behaves like a native app instead of one more browser tab."),
                Ui.Paragraph("Inside a wrapped app:"),
                Ui.Bullets(
                    "**Ctrl+T** opens a new tab at the app’s address; **Ctrl+W** closes the tab (closing the last one closes the window).",
                    "**Ctrl+click** opens a link in a new tab; **Ctrl+H** and **Ctrl+L** (or **Ctrl+Shift+Tab** and **Ctrl+Tab**) switch to the previous and next tab.",
                    "Drag tabs to reorder them. Tabs appear once two or more are open.",
                    "Links to other websites open in your default browser.",
                    "**F12** opens the developer tools.")),
            Section("Two ways to use it",
                Ui.Paragraph("**The window** (this app). Fill in the fields and click **Create App**:"),
                Ui.Bullets(
                    "**App name**: shown in the Start menu and taskbar. Add Start menu folders with “/”: “Web App Wrap/Photos” puts Photos in a Web App Wrap folder.",
                    "**Web address**: where new tabs open.",
                    "**Icon image** (optional): a square image, rounded to the icon shape. Any solid or transparent border is cropped off automatically; the slider zooms in further.",
                    "**Title bar color**: filled in from the site’s theme color; pick another to override it."),
                Ui.Paragraph("To create many apps at once, click **Create from JSON…**."),
                Ui.Paragraph("**The command line.** The same features for scripts and automation, with `waw.exe`. See below.")),
            Section("Command line",
                Ui.Paragraph("`waw.exe` is installed next to Web App Wrap, and the installer adds that folder to your PATH, so you can run `waw` from any terminal:"),
                Ui.CodeBlock(Path.Combine(AppContext.BaseDirectory, "waw.exe")),
                Command("build",
                    "waw build --name <name> --url <address> [--image <file>] [--zoom <1-3>] [--title-bar-color <#RRGGBB>] [--desktop] [--out <folder>]",
                    "Creates one app.",
                    [
                        ("--name", "App name. May include Start menu folders, e.g. \"Web App Wrap/Photos\". Required."),
                        ("--url", "Web address. https:// is added if missing. Required."),
                        ("--image", "Icon image. Without it, a colored tile with the name’s first letter is drawn."),
                        ("--zoom", "1–3, on top of the automatic zoom that crops off the image’s border. Default 1."),
                        ("--title-bar-color", "Hex color such as #1a1a1a. Default: the site’s theme color."),
                        ("--desktop", "Also put a shortcut on the desktop."),
                        ("--out", "Folder for the shortcut (and any folders in its name). Default: the Start menu."),
                    ],
                    "waw build --name \"Linear\" --url linear.app --image %USERPROFILE%\\Pictures\\linear.png"),
                Command("batch",
                    "waw batch <file.json> [--desktop] [--out <folder>]",
                    "Creates every app listed in a JSON file (format below). The whole file is checked first; one failing app doesn’t stop the others. Exits with status 1 if any app failed.",
                    [("--desktop", "Also put shortcuts on the desktop."), ("--out", "Folder for the shortcuts. Default: the Start menu.")],
                    "waw batch apps.json"),
                Command("icon",
                    "waw icon --name <name> [--image <file>] [--zoom <1-3>] --out <file.ico>",
                    "Writes just the .ico icon, using the same rules as build.",
                    [("--out", "Where to write the .ico file. Required.")],
                    "waw icon --name \"Linear\" --out Linear.ico"),
                Ui.Paragraph("Run `waw help` to print a summary of these commands.")),
            Section("Batch file format",
                Ui.Paragraph("A JSON array of objects with the same inputs as the window. Only name and url are required."),
                Ui.CodeBlock("""
                    [
                      {
                        "name": "Web App Wrap/Photos",
                        "url": "https://kphotos.vercel.app",
                        "image": "icons\\photos.png",
                        "zoom": 1.2,
                        "titleBarColor": "#1a1a1a"
                      },
                      { "name": "Linear", "url": "linear.app" }
                    ]
                    """),
                Ui.Bullets(
                    "**image**: relative to the JSON file unless it’s a full path (`~` means your user folder).",
                    "**zoom**: 1–3, on top of the automatic border crop.",
                    "**titleBarColor**: defaults to the site’s theme color.")),
            Section("Good to know",
                Ui.Bullets(
                    "Recreating an app with the same name replaces it and keeps its sign-ins.",
                    $"Each app’s settings, icon and sign-ins are stored in `{AppStore.Root}`. To remove an app, delete its Start menu shortcut and its folder there.",
                    "Every wrapped app runs the installed WebAppWrap.exe, so keep Web App Wrap installed where it is.",
                    "Sites served over https can’t call http:// servers from inside a wrapped app; serve them over https too.")),
            Footer());
        content.Padding = new Thickness(40, 36, 40, 40);

        Content = new ScrollViewer { Content = content, HorizontalScrollMode = ScrollMode.Disabled };
    }

    private static UIElement Header()
    {
        var title = new TextBlock { Text = "Web App Wrap Help", Style = (Style)Application.Current.Resources["TitleTextBlockStyle"] };
        var subtitle = Ui.Caption("Turn any web app into a native Windows app with tabs.");
        subtitle.FontSize = 14;
        return Ui.Stack(6, title, subtitle);
    }

    private static StackPanel Section(string title, params UIElement[] children)
    {
        var heading = new TextBlock { Text = title, Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"] };
        return Ui.Stack(16, [heading, .. children]);
    }

    private static StackPanel Command(string name, string usage, string summary, (string Flag, string Meaning)[] options, string example)
    {
        var heading = new TextBlock { Text = name, FontFamily = Ui.Monospace, FontSize = 18, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold };

        var table = new Grid { ColumnSpacing = 16, RowSpacing = 12 };
        table.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        table.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var i = 0; i < options.Length; i++)
        {
            table.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var flag = new TextBlock { Text = options[i].Flag, FontFamily = Ui.Monospace, IsTextSelectionEnabled = true };
            var meaning = new TextBlock { Text = options[i].Meaning, TextWrapping = TextWrapping.Wrap, LineHeight = 20, IsTextSelectionEnabled = true };
            Grid.SetRow(flag, i);
            Grid.SetRow(meaning, i);
            Grid.SetColumn(meaning, 1);
            table.Children.Add(flag);
            table.Children.Add(meaning);
        }

        var exampleLabel = Ui.Caption("Example");
        exampleLabel.FontSize = 13;
        var block = Ui.Stack(14, heading, Ui.Paragraph(summary), Ui.CodeBlock(usage), table, exampleLabel, Ui.CodeBlock(example));
        block.Margin = new Thickness(0, 10, 0, 0);
        return block;
    }

    private static UIElement Footer()
    {
        var link = new HyperlinkButton { Content = "github.com/carlos-ivan-hernandez/web-app-wrap", NavigateUri = RepositoryUrl, Padding = new Thickness(4, 0, 4, 0) };
        var row = Ui.Row(8, Ui.Icon(""), new TextBlock { Text = "Source code, issues and updates:", VerticalAlignment = VerticalAlignment.Center }, link);
        return Ui.Stack(14, new Border { Height = 1, Background = (Brush)Application.Current.Resources["DividerStrokeColorDefaultBrush"] }, row);
    }
}
