using System.Text.Json;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.Foundation;
using Windows.Graphics;
using Windows.System;
using WebAppWrap.Core;

namespace WebAppWrap.Browser;

/// <summary>
/// A wrapped app's window. The title bar is replaced by a bar in the chosen color holding the
/// tabs, in line with the minimize/maximize/close buttons. Tabs appear once two or more are open;
/// they can be dragged to reorder. Dragging the bar's empty space moves the window.
/// </summary>
internal sealed class BrowserWindow : Window
{
    private const double BarHeight = 48;   // matches TitleBarHeightOption.Tall
    private const double AddButtonWidth = 44;

    private readonly AppConfig _config;
    private readonly LinkPolicy _policy;
    private readonly TitleBarPalette _palette;
    private readonly Grid _bar = new() { Height = BarHeight };
    private readonly ColumnDefinition _captionButtonsColumn = new() { Width = new GridLength(0) };
    private readonly TabView _tabView = new();
    private readonly Grid _pages = new();
    private RectInt32[] _passthrough = [];
    /// <summary>The window's size and position when last not maximized, saved for next launch.</summary>
    private RectInt32 _normalBounds;

    public BrowserWindow(AppConfig config, BrowserWindow? cascadeFrom)
    {
        _config = config;
        _policy = new LinkPolicy(config.BaseUrl);
        _palette = new TitleBarPalette(config.TitleBar);

        Title = config.Name;
        if (File.Exists(AppStore.IconPath(config.Id))) AppWindow.SetIcon(AppStore.IconPath(config.Id));
        ConfigureTitleBar();
        Content = BuildLayout();
        PlaceWindow(cascadeFrom);
        RememberNormalBounds();
        AppWindow.Changed += (_, e) =>
        {
            if (e.DidPositionChange || e.DidSizeChange || e.DidPresenterChange) RememberNormalBounds();
        };

        Closed += (_, _) =>
        {
            SaveWindowState();
            foreach (var tab in Tabs) tab.Close();
        };

        OpenTab(config.BaseUrl);
    }

    private IEnumerable<BrowserTab> Tabs => _tabView.TabItems.OfType<TabViewItem>().Select(item => (BrowserTab)item.Tag);

    private BrowserTab? SelectedTab => (_tabView.SelectedItem as TabViewItem)?.Tag as BrowserTab;

    // ---- Layout ----

    private void ConfigureTitleBar()
    {
        ExtendsContentIntoTitleBar = true;
        var titleBar = AppWindow.TitleBar;
        titleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        titleBar.ButtonBackgroundColor = Colors.Transparent;
        titleBar.ButtonInactiveBackgroundColor = Colors.Transparent;
        titleBar.ButtonForegroundColor = _palette.Foreground;
        titleBar.ButtonInactiveForegroundColor = _palette.ForegroundWithAlpha(0.5);
        titleBar.ButtonHoverForegroundColor = _palette.Foreground;
        titleBar.ButtonHoverBackgroundColor = _palette.ForegroundWithAlpha(0.1);
        titleBar.ButtonPressedForegroundColor = _palette.Foreground;
        titleBar.ButtonPressedBackgroundColor = _palette.ForegroundWithAlpha(0.18);
    }

    private UIElement BuildLayout()
    {
        _bar.Background = _palette.Brush(_palette.Background);
        _bar.RequestedTheme = _palette.Theme;
        _bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
        _bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        _bar.ColumnDefinitions.Add(_captionButtonsColumn);

        _palette.ApplyTo(_tabView.Resources);
        _tabView.IsAddTabButtonVisible = true;
        _tabView.CanReorderTabs = true;
        _tabView.CanDragTabs = false;
        _tabView.TabWidthMode = TabViewWidthMode.Equal;
        _tabView.VerticalAlignment = VerticalAlignment.Bottom;
        _tabView.Visibility = Visibility.Collapsed;
        _tabView.AddTabButtonClick += (_, _) => NewTab();
        _tabView.TabCloseRequested += (_, e) => CloseTab((BrowserTab)e.Tab.Tag);
        _tabView.SelectionChanged += (_, _) => ShowSelectedTab();
        _tabView.TabItemsChanged += (_, _) => UpdateTabStrip();
        Grid.SetColumn(_tabView, 1);
        _bar.Children.Add(_tabView);

        // The whole bar drags the window, except the tabs and "+" (see UpdateDragRegions).
        SetTitleBar(_bar);
        _bar.SizeChanged += (_, _) => UpdateDragRegions();
        _tabView.LayoutUpdated += (_, _) => UpdateDragRegions();

        var root = new Grid { Background = _palette.Brush(_palette.Background) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.Children.Add(_bar);
        Grid.SetRow(_pages, 1);
        root.Children.Add(_pages);
        AddKeyboardShortcuts(root);
        return root;
    }

    /// <summary>
    /// Makes the tabs and "+" clickable (and draggable for reordering) instead of moving the
    /// window. Only the bar's empty space stays a window drag area.
    /// </summary>
    private void UpdateDragRegions()
    {
        if (_bar.XamlRoot is null) return;
        var scale = _bar.XamlRoot.RasterizationScale;
        _captionButtonsColumn.Width = new GridLength(AppWindow.TitleBar.RightInset / scale);

        var regions = new List<RectInt32>();
        if (_tabView.Visibility == Visibility.Visible && _tabView.TabItems.Count > 0)
        {
            var left = _tabView.TransformToVisual(null).TransformPoint(new Point(0, 0)).X;
            var right = left;
            foreach (var item in _tabView.TabItems.OfType<TabViewItem>())
                right = Math.Max(right, item.TransformToVisual(null).TransformPoint(new Point(item.ActualWidth, 0)).X);
            right += AddButtonWidth;
            regions.Add(new RectInt32(
                (int)Math.Floor(left * scale), 0,
                (int)Math.Ceiling((right - left) * scale), (int)Math.Ceiling(BarHeight * scale)));
        }

        var rects = regions.ToArray();
        if (rects.SequenceEqual(_passthrough)) return;
        _passthrough = rects;
        InputNonClientPointerSource.GetForWindowId(AppWindow.Id).SetRegionRects(NonClientRegionKind.Passthrough, rects);
    }

    // ---- Tabs ----

    /// <summary>Adds a tab. Link-opened tabs go right after their opener; others go at the end.</summary>
    public BrowserTab OpenTab(Uri? url, BrowserTab? after = null, bool activate = true)
    {
        var tab = new BrowserTab(this, _policy);
        tab.WebView.Visibility = Visibility.Collapsed;
        _pages.Children.Add(tab.WebView);

        var index = after is null ? _tabView.TabItems.Count : _tabView.TabItems.IndexOf(after.Item) + 1;
        _tabView.TabItems.Insert(Math.Clamp(index, 0, _tabView.TabItems.Count), tab.Item);
        if (activate || _tabView.SelectedItem is null) _tabView.SelectedItem = tab.Item;

        if (url is not null) _ = tab.NavigateAsync(url);
        else _ = tab.InitializeAsync();
        return tab;
    }

    /// <summary>Closing the last tab closes the window; closing the last window quits the app.</summary>
    public void CloseTab(BrowserTab tab)
    {
        var index = _tabView.TabItems.IndexOf(tab.Item);
        if (index < 0) return;
        if (_tabView.TabItems.Count == 1)
        {
            Close();
            return;
        }
        var wasSelected = ReferenceEquals(_tabView.SelectedItem, tab.Item);
        _tabView.TabItems.RemoveAt(index);
        _pages.Children.Remove(tab.WebView);
        tab.Close();
        if (wasSelected) _tabView.SelectedIndex = Math.Min(index, _tabView.TabItems.Count - 1);
    }

    public void TabDidChange(BrowserTab tab)
    {
        if (tab == SelectedTab) Title = tab.Title;
    }

    private void ShowSelectedTab()
    {
        var selected = SelectedTab;
        foreach (var tab in Tabs)
            tab.WebView.Visibility = tab == selected ? Visibility.Visible : Visibility.Collapsed;
        if (selected is null) return;
        Title = selected.Title;
        selected.WebView.Focus(FocusState.Programmatic);
    }

    /// <summary>Tabs only show once there are two or more; with one, the bar is a plain title bar.</summary>
    private void UpdateTabStrip()
    {
        _tabView.Visibility = _tabView.TabItems.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        UpdateDragRegions();
    }

    private void SelectTab(int offset)
    {
        var count = _tabView.TabItems.Count;
        if (count < 2) return;
        _tabView.SelectedIndex = ((_tabView.SelectedIndex + offset) % count + count) % count;
    }

    private void SelectTabNumber(int number)
    {
        var count = _tabView.TabItems.Count;
        var index = number == 9 ? count - 1 : number - 1;
        if (index >= 0 && index < count) _tabView.SelectedIndex = index;
    }

    private void NewTab() => OpenTab(_config.BaseUrl);

    // ---- Shortcuts ----

    /// <summary>Commands sent by BrowserTab's page script when a page has keyboard focus.</summary>
    public void RunCommand(string command)
    {
        switch (command)
        {
            case "newTab": NewTab(); break;
            case "closeTab": if (SelectedTab is { } tab) CloseTab(tab); break;
            case "closeWindow": Close(); break;
            case "newWindow": App.Instance?.OpenBrowserWindow(this); break;
            case "nextTab": SelectTab(1); break;
            case "previousTab": SelectTab(-1); break;
            default:
                if (command.StartsWith("tab", StringComparison.Ordinal) && int.TryParse(command[3..], out var number))
                    SelectTabNumber(number);
                break;
        }
    }

    /// <summary>The same shortcuts when focus is outside the page (e.g. on the tab strip).</summary>
    private void AddKeyboardShortcuts(UIElement root)
    {
        void Add(VirtualKey key, VirtualKeyModifiers modifiers, string command)
        {
            var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
            accelerator.Invoked += (_, e) =>
            {
                e.Handled = true;
                RunCommand(command);
            };
            root.KeyboardAccelerators.Add(accelerator);
        }

        const VirtualKeyModifiers ctrl = VirtualKeyModifiers.Control;
        Add(VirtualKey.T, ctrl, "newTab");
        Add(VirtualKey.W, ctrl, "closeTab");
        Add(VirtualKey.W, ctrl | VirtualKeyModifiers.Shift, "closeWindow");
        Add(VirtualKey.N, ctrl, "newWindow");
        Add(VirtualKey.Tab, ctrl, "nextTab");
        Add(VirtualKey.Tab, ctrl | VirtualKeyModifiers.Shift, "previousTab");
        Add(VirtualKey.L, ctrl, "nextTab");
        Add(VirtualKey.H, ctrl, "previousTab");
        for (var number = 1; number <= 9; number++)
            Add(VirtualKey.Number0 + number, ctrl, $"tab{number}");
        root.KeyboardAcceleratorPlacementMode = KeyboardAcceleratorPlacementMode.Hidden;
    }

    // ---- Full screen (a page's video or fullscreen API) ----

    public void SetFullScreen(bool fullScreen)
    {
        AppWindow.SetPresenter(fullScreen ? AppWindowPresenterKind.FullScreen : AppWindowPresenterKind.Overlapped);
        _bar.Visibility = fullScreen ? Visibility.Collapsed : Visibility.Visible;
    }

    // ---- Window size and position ----

    private sealed record WindowState(int X, int Y, int Width, int Height, bool Maximized);

    private void PlaceWindow(BrowserWindow? cascadeFrom)
    {
        if (cascadeFrom is not null)
        {
            var from = cascadeFrom.AppWindow;
            AppWindow.MoveAndResize(new RectInt32(from.Position.X + 32, from.Position.Y + 32, from.Size.Width, from.Size.Height));
            return;
        }

        try
        {
            var saved = JsonSerializer.Deserialize<WindowState>(File.ReadAllText(AppStore.WindowStatePath(_config.Id)));
            if (saved is not null && saved.Width > 200 && saved.Height > 150)
            {
                var rect = new RectInt32(saved.X, saved.Y, saved.Width, saved.Height);
                // Only restore if it's still on a connected display.
                var area = DisplayArea.GetFromRect(rect, DisplayAreaFallback.None);
                if (area is not null)
                {
                    AppWindow.MoveAndResize(rect);
                    if (saved.Maximized && AppWindow.Presenter is OverlappedPresenter presenter) presenter.Maximize();
                    return;
                }
            }
        }
        catch (Exception exception) when (exception is IOException or JsonException or UnauthorizedAccessException)
        {
            // First launch, or unreadable: fall through to the default size.
        }

        var work = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var width = Math.Min(1280, (int)(work.Width * 0.85));
        var height = Math.Min(860, (int)(work.Height * 0.85));
        AppWindow.MoveAndResize(new RectInt32(work.X + (work.Width - width) / 2, work.Y + (work.Height - height) / 2, width, height));
    }

    private void RememberNormalBounds()
    {
        if (AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Restored })
            _normalBounds = new RectInt32(AppWindow.Position.X, AppWindow.Position.Y, AppWindow.Size.Width, AppWindow.Size.Height);
    }

    private void SaveWindowState()
    {
        try
        {
            var maximized = AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Maximized };
            var state = new WindowState(_normalBounds.X, _normalBounds.Y, _normalBounds.Width, _normalBounds.Height, maximized);
            File.WriteAllText(AppStore.WindowStatePath(_config.Id), JsonSerializer.Serialize(state));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Not worth interrupting closing over.
        }
    }
}
