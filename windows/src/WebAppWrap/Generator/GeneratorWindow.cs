using System.Diagnostics;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using SkiaSharp;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;
using WebAppWrap.Core;
using WebAppWrap.Core.Icons;
using Color = Windows.UI.Color;
using IconSource = WebAppWrap.Core.Icons.IconSource;

namespace WebAppWrap.Generator;

/// <summary>The Web App Wrap window: name, web address, icon and title bar color in; a Start menu app out.</summary>
internal sealed class GeneratorWindow : Window
{
    private enum ColorSource { Standard, LookingUp, Site, Custom }

    // State
    private SKBitmap? _image;
    private string _imageFileName = "";
    /// <summary>The automatic zoom that crops off the image's border; the slider zooms in from here.</summary>
    private double _baseZoom = 1;
    private HexColor _titleBarColor = HexColor.DefaultTitleBar;
    private ColorSource _colorSource = ColorSource.Standard;
    private CancellationTokenSource? _themeLookup;
    private bool _busy;
    private bool _settingColor;
    private HelpWindow? _help;

    // Controls
    private readonly Image _preview = new() { Width = 160, Height = 160, Stretch = Stretch.Uniform };
    private readonly Button _useDefaultImage = new() { Content = "Use Default" };
    private readonly Slider _zoom = new() { Minimum = IconSource.MinUserZoom, Maximum = IconSource.MaxUserZoom, StepFrequency = 0.01, Value = 1, Width = 128 };
    private readonly StackPanel _zoomRow;
    private readonly TextBlock _imageCaption = Ui.Caption("Default icon. Drop an image here to use your own.");

    private readonly TextBox _name = new() { PlaceholderText = "e.g. Linear, or Web App Wrap/Linear" };
    private readonly TextBlock _nameCaption = Ui.Caption();
    private readonly TextBox _url = new() { PlaceholderText = "e.g. linear.app" };
    private readonly TextBlock _urlCaption = Ui.Caption();

    private readonly Border _swatch = new() { Width = 22, Height = 22, CornerRadius = new CornerRadius(4), BorderThickness = new Thickness(1) };
    private readonly TextBlock _hex = new() { FontFamily = Ui.Monospace, VerticalAlignment = VerticalAlignment.Center };
    private readonly ColorPicker _picker = new() { IsAlphaEnabled = false, IsMoreButtonVisible = false, IsColorChannelTextInputVisible = false };
    private readonly ProgressRing _colorSpinner = new() { Width = 16, Height = 16, IsActive = false, Visibility = Visibility.Collapsed };
    private readonly TextBlock _colorSourceText = Ui.Caption();
    private readonly HyperlinkButton _useSiteColor = new() { Content = "Use Site Color", Padding = new Thickness(4, 0, 4, 0), Visibility = Visibility.Collapsed };

    private readonly CheckBox _desktopShortcut = new() { Content = "Also add a shortcut to the desktop" };

    private readonly ProgressRing _busySpinner = new() { Width = 16, Height = 16, IsActive = false, Visibility = Visibility.Collapsed };
    private readonly FontIcon _statusIcon = Ui.Icon("", 16);
    private readonly TextBlock _status = new() { VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly HyperlinkButton _openApp = new() { Content = "Open" };
    private readonly HyperlinkButton _showInFolder = new() { Content = "Show in Folder" };
    private readonly Button _createFromJson = new() { Content = "Create from JSON…" };
    private readonly Button _create = new() { Content = "Create App" };

    private string? _lastShortcut;

    public GeneratorWindow()
    {
        Title = "Web App Wrap";
        SystemBackdrop = new MicaBackdrop();
        ExtendsContentIntoTitleBar = true;
        var icon = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
        if (File.Exists(icon)) AppWindow.SetIcon(icon);

        _zoomRow = Ui.Row(8, Ui.Icon(""), _zoom, Ui.Icon(""));
        _zoomRow.Visibility = Visibility.Collapsed;
        _zoomRow.HorizontalAlignment = HorizontalAlignment.Center;
        ToolTipService.SetToolTip(_zoomRow, "Zoom in on the image");

        Content = BuildLayout();
        SizeWindow(780, 640);
        WireEvents();
        UpdateNameCaption();
        UpdateUrlCaption();
        ShowTitleBarColor();
        ShowStatus(null);
        RefreshPreview();
    }

    // ---- Layout ----

    private UIElement BuildLayout()
    {
        var titleBar = Ui.Row(10);
        titleBar.Height = 40;
        titleBar.Padding = new Thickness(16, 0, 0, 0);
        var appIcon = Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico");
        if (File.Exists(appIcon)) titleBar.Children.Add(new ImageIcon { Source = new BitmapImage(new Uri(appIcon)), Width = 16, Height = 16 });
        titleBar.Children.Add(new TextBlock { Text = "Web App Wrap", VerticalAlignment = VerticalAlignment.Center, Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"] });
        SetTitleBar(titleBar);

        var body = new Grid { ColumnSpacing = 36, Padding = new Thickness(32, 16, 32, 24) };
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(200) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        body.Children.Add(BuildIconColumn());
        var fields = BuildFieldsColumn();
        Grid.SetColumn(fields, 1);
        body.Children.Add(fields);

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.Children.Add(titleBar);
        var scroller = new ScrollViewer { Content = body };
        Grid.SetRow(scroller, 1);
        root.Children.Add(scroller);
        var footer = BuildFooter();
        Grid.SetRow(footer, 2);
        root.Children.Add(footer);
        return root;
    }

    private UIElement BuildIconColumn()
    {
        var dropTarget = new Grid { AllowDrop = true, Background = new SolidColorBrush(Colors.Transparent), Padding = new Thickness(8) };
        dropTarget.Children.Add(_preview);
        dropTarget.DragOver += (_, e) =>
        {
            if (e.DataView.Contains(StandardDataFormats.StorageItems)) e.AcceptedOperation = DataPackageOperation.Copy;
        };
        dropTarget.Drop += async (_, e) =>
        {
            if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;
            var items = await e.DataView.GetStorageItemsAsync();
            if (items.FirstOrDefault() is StorageFile file) LoadImage(file.Path);
        };
        ToolTipService.SetToolTip(dropTarget, "Drop an image here");

        var choose = new Button { Content = "Choose Image…" };
        choose.Click += async (_, _) => await ChooseImageAsync();
        _useDefaultImage.Click += (_, _) => ClearImage();
        _useDefaultImage.Visibility = Visibility.Collapsed;
        var buttons = Ui.Row(8, choose, _useDefaultImage);
        buttons.HorizontalAlignment = HorizontalAlignment.Center;

        _imageCaption.TextAlignment = TextAlignment.Center;
        _imageCaption.MaxLines = 2;
        _imageCaption.TextTrimming = TextTrimming.CharacterEllipsis;

        return Ui.Stack(12, dropTarget, buttons, _zoomRow, _imageCaption);
    }

    private FrameworkElement BuildFieldsColumn()
    {
        var colorButton = new Button
        {
            Content = Ui.Row(10, _swatch, _hex),
            Flyout = new Flyout { Content = _picker, Placement = FlyoutPlacementMode.Bottom },
            Padding = new Thickness(8, 6, 12, 6),
        };
        _useSiteColor.Click += (_, _) =>
        {
            _colorSource = ColorSource.Standard;
            LookUpThemeColor(immediately: true);
        };
        var colorRow = Ui.Row(12, colorButton, _colorSpinner, _colorSourceText, _useSiteColor);
        _colorSourceText.VerticalAlignment = VerticalAlignment.Center;
        _colorSpinner.VerticalAlignment = VerticalAlignment.Center;

        return Ui.Stack(22,
            Ui.Stack(6, Ui.Label("App name"), _name, _nameCaption),
            Ui.Stack(6, Ui.Label("Web address"), _url, _urlCaption),
            Ui.Stack(6, Ui.Label("Title bar color"), colorRow,
                Ui.Caption("Background of the bar holding the window buttons and tabs.")),
            _desktopShortcut);
    }

    private FrameworkElement BuildFooter()
    {
        var help = new Button { Content = Ui.Icon("", 16), Padding = new Thickness(8) };
        ToolTipService.SetToolTip(help, "Web App Wrap Help");
        help.Click += (_, _) => ShowHelp();

        _create.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
        _create.Click += async (_, _) => await CreateAppAsync();
        _createFromJson.Click += async (_, _) => await CreateFromJsonAsync();
        ToolTipService.SetToolTip(_createFromJson, "Create several apps from a JSON file");
        _openApp.Click += (_, _) => { if (_lastShortcut is not null) Open(_lastShortcut); };
        _showInFolder.Click += (_, _) => { if (_lastShortcut is not null) ShowInFolder(_lastShortcut); };

        var status = Ui.Row(8, _busySpinner, _statusIcon, _status, _openApp, _showInFolder);
        status.VerticalAlignment = VerticalAlignment.Center;

        var footer = new Grid
        {
            ColumnSpacing = 12,
            Padding = new Thickness(24, 14, 24, 14),
            BorderThickness = new Thickness(0, 1, 0, 0),
            BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
            Background = (Brush)Application.Current.Resources["LayerFillColorDefaultBrush"],
        };
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.Children.Add(help);
        Grid.SetColumn(status, 1);
        footer.Children.Add(status);
        Grid.SetColumn(_createFromJson, 2);
        footer.Children.Add(_createFromJson);
        Grid.SetColumn(_create, 3);
        footer.Children.Add(_create);
        return footer;
    }

    private void SizeWindow(int width, int height)
    {
        var scale = NativeMethods.GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96.0;
        AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(width * scale), (int)(height * scale)));
        var work = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        AppWindow.Move(new Windows.Graphics.PointInt32(
            work.X + (work.Width - AppWindow.Size.Width) / 2,
            work.Y + (work.Height - AppWindow.Size.Height) / 2));
    }

    private void WireEvents()
    {
        _name.TextChanged += (_, _) =>
        {
            UpdateNameCaption();
            if (_image is null) RefreshPreview();
            UpdateCreateButton();
        };
        _url.TextChanged += (_, _) =>
        {
            UpdateUrlCaption();
            LookUpThemeColor(immediately: false);
            UpdateCreateButton();
        };
        _url.KeyDown += async (_, e) =>
        {
            if (e.Key == Windows.System.VirtualKey.Enter) await CreateAppAsync();
        };
        _zoom.ValueChanged += (_, _) => RefreshPreview();
        _picker.ColorChanged += (_, e) =>
        {
            if (_settingColor) return;
            _themeLookup?.Cancel();
            _titleBarColor = HexColor.FromBytes(e.NewColor.R, e.NewColor.G, e.NewColor.B);
            _colorSource = ColorSource.Custom;
            ShowTitleBarColor();
        };
        UpdateCreateButton();
    }

    // ---- Name and address ----

    private AppLocation Location => new(_name.Text);
    private Uri? NormalizedUrl => InputNormalizer.NormalizeUrl(_url.Text);

    private void UpdateNameCaption() =>
        _nameCaption.Text = Location.Name.Length == 0
            ? "Shown in the Start menu and taskbar. Add Start menu folders with “/”."
            : $"Start menu › {Location.DisplayPath}";

    private void UpdateUrlCaption()
    {
        if (_url.Text.Trim().Length == 0)
        {
            _urlCaption.Text = "New tabs open here. Links to other sites open in your browser.";
            _urlCaption.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        }
        else if (NormalizedUrl is { } url)
        {
            _urlCaption.Text = $"Opens {url.AbsoluteUri}";
            _urlCaption.Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        }
        else
        {
            _urlCaption.Text = "Enter a web address like example.com or https://example.com/app.";
            _urlCaption.Foreground = (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"];
        }
    }

    private void UpdateCreateButton()
    {
        _create.IsEnabled = !_busy && Location.Name.Length > 0 && NormalizedUrl is not null;
        _createFromJson.IsEnabled = !_busy;
    }

    // ---- Icon ----

    private IconSource CurrentIcon => _image is not null
        ? new IconSource.Image(_image, _baseZoom * _zoom.Value)
        : new IconSource.Generated(Location.Name);

    private void RefreshPreview()
    {
        using var rendered = IconRenderer.Render(CurrentIcon, 320);
        using var bgra = rendered.Copy(SKColorType.Bgra8888);
        var bitmap = new WriteableBitmap(bgra.Width, bgra.Height);
        using (var stream = bitmap.PixelBuffer.AsStream()) stream.Write(bgra.Bytes);
        bitmap.Invalidate();
        _preview.Source = bitmap;
    }

    private async Task ChooseImageAsync()
    {
        var picker = new FileOpenPicker { SuggestedStartLocation = PickerLocationId.PicturesLibrary, ViewMode = PickerViewMode.Thumbnail };
        foreach (var type in new[] { ".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp", ".ico" }) picker.FileTypeFilter.Add(type);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        if (await picker.PickSingleFileAsync() is { } file) LoadImage(file.Path);
    }

    private void LoadImage(string path)
    {
        if (IconRenderer.LoadImage(path) is not { } image)
        {
            ShowStatus("That file isn’t an image Web App Wrap can read.", isError: true);
            return;
        }
        _image?.Dispose();
        _image = image;
        _imageFileName = Path.GetFileName(path);
        _baseZoom = IconRenderer.AutomaticZoom(image);
        _zoom.Value = 1;
        _zoomRow.Visibility = Visibility.Visible;
        _useDefaultImage.Visibility = Visibility.Visible;
        _imageCaption.Text = _imageFileName;
        RefreshPreview();
    }

    private void ClearImage()
    {
        _image?.Dispose();
        _image = null;
        _imageFileName = "";
        _zoomRow.Visibility = Visibility.Collapsed;
        _useDefaultImage.Visibility = Visibility.Collapsed;
        _imageCaption.Text = "Default icon. Drop an image here to use your own.";
        RefreshPreview();
    }

    // ---- Title bar color ----

    /// <summary>Fetches the site's theme color shortly after the address stops changing, unless a color was picked.</summary>
    private async void LookUpThemeColor(bool immediately)
    {
        _themeLookup?.Cancel();
        if (_colorSource == ColorSource.Custom || NormalizedUrl is not { } url) return;

        var lookup = _themeLookup = new CancellationTokenSource();
        _colorSource = ColorSource.LookingUp;
        ShowTitleBarColor();
        try
        {
            if (!immediately) await Task.Delay(600, lookup.Token);
            var found = await ThemeColor.FetchAsync(url, lookup.Token);
            if (lookup.IsCancellationRequested || _colorSource == ColorSource.Custom) return;
            _titleBarColor = found ?? HexColor.DefaultTitleBar;
            _colorSource = found is null ? ColorSource.Standard : ColorSource.Site;
            ShowTitleBarColor();
        }
        catch (OperationCanceledException)
        {
            // Superseded by a newer address or a picked color.
        }
    }

    private void ShowTitleBarColor()
    {
        var color = Color.FromArgb(255, _titleBarColor.R, _titleBarColor.G, _titleBarColor.B);
        _swatch.Background = new SolidColorBrush(color);
        _swatch.BorderBrush = (Brush)Application.Current.Resources["ControlStrokeColorDefaultBrush"];
        _hex.Text = _titleBarColor.ToHex();
        _settingColor = true;
        _picker.Color = color;
        _settingColor = false;

        var looking = _colorSource == ColorSource.LookingUp;
        _colorSpinner.IsActive = looking;
        _colorSpinner.Visibility = looking ? Visibility.Visible : Visibility.Collapsed;
        _useSiteColor.Visibility = _colorSource == ColorSource.Custom ? Visibility.Visible : Visibility.Collapsed;
        _colorSourceText.Text = _colorSource switch
        {
            ColorSource.LookingUp => "Checking the site’s theme color…",
            ColorSource.Site => "From the site’s theme color",
            ColorSource.Custom => "Custom",
            _ => NormalizedUrl is null ? "Default" : "Default (the site has no theme color)",
        };
    }

    // ---- Creating apps ----

    private async Task CreateAppAsync()
    {
        if (_busy || NormalizedUrl is not { } url || Location.Name.Length == 0) return;
        var location = Location;
        var root = AppBuilder.StartMenuPrograms;
        var shortcut = location.ShortcutPath(root);

        if (File.Exists(shortcut) && !await ConfirmAsync(
                $"Replace “{location.Name}”?",
                $"An app already exists at Start menu › {location.DisplayPath}. It will be replaced. Its sign-ins and settings are kept.",
                "Replace"))
            return;

        SetBusy(true, $"Creating {location.Name}…");
        try
        {
            var spec = new AppSpec(location, url, CurrentIcon, _titleBarColor);
            var desktop = _desktopShortcut.IsChecked == true;
            _lastShortcut = await Task.Run(() => AppBuilder.Build(spec, root, desktop));
            ShowStatus($"Created {location.Name}", shortcut: _lastShortcut);
        }
        catch (Exception exception)
        {
            ShowStatus(exception.Message, isError: true);
        }
        finally
        {
            SetBusy(false);
        }
    }

    /// <summary>Asks for a JSON file (see BatchFile for the format), confirms, then builds every app in it.</summary>
    private async Task CreateFromJsonAsync()
    {
        if (_busy) return;
        var picker = new FileOpenPicker();
        foreach (var extension in BatchFile.Extensions) picker.FileTypeFilter.Add(extension);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        if (await picker.PickSingleFileAsync() is not { } file) return;

        IReadOnlyList<BatchEntry> entries;
        try
        {
            entries = BatchFile.Parse(await File.ReadAllTextAsync(file.Path), Path.GetDirectoryName(file.Path)!);
        }
        catch (Exception exception) when (exception is BatchFileException or IOException)
        {
            await ShowMessageAsync($"{file.Name} can’t be used", exception.Message);
            return;
        }

        var root = AppBuilder.StartMenuPrograms;
        var existing = entries.Count(entry => File.Exists(entry.Location.ShortcutPath(root)));
        var details = string.Join("\n", entries.Take(12).Select(entry => $"Start menu › {entry.Location.DisplayPath}"));
        if (entries.Count > 12) details += $"\n…and {entries.Count - 12} more";
        if (existing > 0)
            details += $"\n\n{existing} already exist{(existing == 1 ? "s" : "")} and will be replaced. Their sign-ins and settings are kept.";
        if (!await ConfirmAsync($"Create {entries.Count} app{(entries.Count == 1 ? "" : "s")}?", details, "Create")) return;

        SetBusy(true, $"Building 1 of {entries.Count}: {entries[0].Location.Name}…");
        try
        {
            var results = await AppBuilder.BuildBatchAsync(entries, root, _desktopShortcut.IsChecked == true, (index, entry) =>
                _status.Text = $"Building {index + 1} of {entries.Count}: {entry.Location.Name}…");
            var failures = results.Where(result => result.Error is not null).ToList();
            _lastShortcut = results.LastOrDefault(result => result.Shortcut is not null)?.Shortcut;
            ShowStatus(
                failures.Count == 0 ? $"Created {results.Count} apps" : $"Created {results.Count - failures.Count}, {failures.Count} failed",
                isError: failures.Count > 0,
                shortcut: _lastShortcut,
                showOpen: false);
            if (failures.Count > 0)
            {
                await ShowMessageAsync(
                    $"{failures.Count} of {results.Count} apps couldn’t be created",
                    string.Join("\n", failures.Select(failure => $"{failure.Entry.Location.Name}: {failure.Error!.Message}")));
            }
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void SetBusy(bool busy, string? message = null)
    {
        _busy = busy;
        _busySpinner.IsActive = busy;
        _busySpinner.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        if (busy) ShowStatus(message);
        UpdateCreateButton();
    }

    private void ShowStatus(string? message, bool isError = false, string? shortcut = null, bool showOpen = true)
    {
        _status.Text = message ?? "";
        _statusIcon.Visibility = message is not null && !_busy ? Visibility.Visible : Visibility.Collapsed;
        _statusIcon.Glyph = isError ? "" : "";
        _statusIcon.Foreground = (Brush)Application.Current.Resources[isError ? "SystemFillColorCautionBrush" : "SystemFillColorSuccessBrush"];
        _openApp.Visibility = shortcut is not null && showOpen ? Visibility.Visible : Visibility.Collapsed;
        _showInFolder.Visibility = shortcut is not null ? Visibility.Visible : Visibility.Collapsed;
        ToolTipService.SetToolTip(_status, message);
    }

    private static void Open(string shortcut) =>
        Process.Start(new ProcessStartInfo(shortcut) { UseShellExecute = true });

    private static void ShowInFolder(string path) =>
        Process.Start("explorer.exe", $"/select,\"{path}\"");

    // ---- Dialogs ----

    private async Task<bool> ConfirmAsync(string title, string message, string primary)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = title,
            Content = new ScrollViewer { Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, LineHeight = 22 }, MaxHeight = 360 },
            PrimaryButtonText = primary,
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    private async Task ShowMessageAsync(string title, string message)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = title,
            Content = new ScrollViewer { Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, LineHeight = 22 }, MaxHeight = 360 },
            CloseButtonText = "OK",
        };
        await dialog.ShowAsync();
    }

    private void ShowHelp()
    {
        if (_help is null)
        {
            _help = new HelpWindow();
            _help.Closed += (_, _) => _help = null;
        }
        _help.Activate();
    }
}
