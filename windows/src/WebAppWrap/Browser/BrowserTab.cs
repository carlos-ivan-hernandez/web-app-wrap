using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using WebAppWrap.Core;

namespace WebAppWrap.Browser;

/// <summary>
/// One tab: a WebView2 plus the rules for where its links go. The owning BrowserWindow shows its
/// web view and puts <see cref="Item"/> in the tab strip.
/// </summary>
internal sealed class BrowserTab
{
    /// <summary>
    /// Forwards the window's shortcuts while a page has keyboard focus (WebView2 swallows them
    /// otherwise). Runs in every page before its own scripts, in the capture phase.
    /// </summary>
    private const string ShortcutScript = """
        (() => {
          if (window.__webAppWrap) return;
          window.__webAppWrap = true;
          addEventListener('keydown', (e) => {
            if (!e.ctrlKey || e.altKey || e.metaKey) return;
            const k = e.key.toLowerCase();
            let command = null;
            if (k === 'tab') command = e.shiftKey ? 'previousTab' : 'nextTab';
            else if (e.shiftKey) { if (k === 'w') command = 'closeWindow'; }
            else if (k === 't') command = 'newTab';
            else if (k === 'w') command = 'closeTab';
            else if (k === 'n') command = 'newWindow';
            else if (k === 'h') command = 'previousTab';
            else if (k === 'l') command = 'nextTab';
            else if (k >= '1' && k <= '9') command = 'tab' + k;
            if (command && window.chrome && chrome.webview) {
              e.preventDefault();
              e.stopImmediatePropagation();
              chrome.webview.postMessage('webappwrap:' + command);
            }
          }, true);
        })();
        """;

    private readonly BrowserWindow _owner;
    private readonly LinkPolicy _policy;
    private readonly TextBlock _title = new() { TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
    private readonly ProgressRing _spinner = new() { Width = 14, Height = 14, IsActive = false, Visibility = Visibility.Collapsed, Margin = new Thickness(0, 0, 8, 0) };
    private Task? _initialization;
    private bool _hasShownPage;

    public WebView2 WebView { get; } = new();
    public TabViewItem Item { get; }

    public BrowserTab(BrowserWindow owner, LinkPolicy policy)
    {
        _owner = owner;
        _policy = policy;
        _title.Text = "New Tab";
        var header = new StackPanel { Orientation = Orientation.Horizontal };
        header.Children.Add(_spinner);
        header.Children.Add(_title);
        Item = new TabViewItem { Header = header, Tag = this, IsClosable = true };
        ToolTipService.SetToolTip(Item, _title.Text);
    }

    public string Title => _title.Text;

    public CoreWebView2? Core => WebView.CoreWebView2;

    /// <summary>Creates the browser engine for this tab. Safe to call more than once.</summary>
    public Task InitializeAsync() => _initialization ??= InitializeCoreAsync();

    private async Task InitializeCoreAsync()
    {
        var environment = await App.Instance!.WebViewEnvironment;
        await WebView.EnsureCoreWebView2Async(environment);
        var core = WebView.CoreWebView2;

        core.Settings.AreDevToolsEnabled = true;   // F12, Ctrl+Shift+I, and right-click > Inspect
        core.Settings.IsStatusBarEnabled = true;
        await core.AddScriptToExecuteOnDocumentCreatedAsync(ShortcutScript);

        core.DocumentTitleChanged += (_, _) => UpdateTitle();
        core.NavigationStarting += OnNavigationStarting;
        core.NavigationCompleted += (_, _) =>
        {
            _hasShownPage = true;
            SetLoading(false);
            UpdateTitle();
        };
        core.NewWindowRequested += OnNewWindowRequested;
        core.LaunchingExternalUriScheme += OnLaunchingExternalUriScheme;
        core.WindowCloseRequested += (_, _) => _owner.CloseTab(this);
        core.WebMessageReceived += OnWebMessageReceived;
        core.ContainsFullScreenElementChanged += (_, _) => _owner.SetFullScreen(core.ContainsFullScreenElement);
        core.ProcessFailed += (_, e) =>
        {
            if (e.ProcessFailedKind is CoreWebView2ProcessFailedKind.RenderProcessExited or CoreWebView2ProcessFailedKind.RenderProcessUnresponsive)
                core.Reload();
        };
    }

    public async Task NavigateAsync(Uri url)
    {
        await InitializeAsync();
        WebView.CoreWebView2.Navigate(url.AbsoluteUri);
    }

    public void Reload() => Core?.Reload();

    public void Close()
    {
        WebView.Close();
    }

    private void UpdateTitle()
    {
        var title = Core?.DocumentTitle?.Trim();
        if (string.IsNullOrEmpty(title) && Uri.TryCreate(Core?.Source, UriKind.Absolute, out var source) && source.Scheme.StartsWith("http"))
            title = source.Host;
        _title.Text = string.IsNullOrEmpty(title) ? "New Tab" : title;
        ToolTipService.SetToolTip(Item, _title.Text);
        _owner.TabDidChange(this);
    }

    private void SetLoading(bool loading)
    {
        _spinner.IsActive = loading;
        _spinner.Visibility = loading ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>A tab that never showed a page (it only led to a browser hand-off or another app) is closed.</summary>
    private void CloseIfFresh()
    {
        if (!_hasShownPage) _owner.DispatcherQueue.TryEnqueue(() => _owner.CloseTab(this));
    }

    private static void OpenExternally(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch (Exception exception) when (exception is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            // No app is registered for this link; nothing else to do.
        }
    }

    // ---- Where links go ----

    private void OnNavigationStarting(CoreWebView2 sender, CoreWebView2NavigationStartingEventArgs e)
    {
        // Only clicks are routed. Redirects and scripted navigations to other sites stay in the
        // app so sign-in flows (SSO, OAuth) keep working. A new tab's first load was already
        // routed when the tab was opened (e.g. a sign-in popup that must stay in the app).
        if (_hasShownPage && e.IsUserInitiated && !e.IsRedirected && _policy.DestinationFor(e.Uri) == LinkDestination.Browser)
        {
            e.Cancel = true;
            OpenExternally(e.Uri);
            return;
        }
        SetLoading(true);
    }

    /// <summary>mailto:, tel:, zoommtg: and the like go straight to the app that handles them.</summary>
    private void OnLaunchingExternalUriScheme(CoreWebView2 sender, CoreWebView2LaunchingExternalUriSchemeEventArgs e)
    {
        e.Cancel = true;
        if (e.IsUserInitiated || _hasShownPage) OpenExternally(e.Uri);
        CloseIfFresh();
    }

    /// <summary>Ctrl+click, target=_blank and window.open.</summary>
    private async void OnNewWindowRequested(CoreWebView2 sender, CoreWebView2NewWindowRequestedEventArgs e)
    {
        e.Handled = true;
        var destination = _policy.DestinationFor(e.Uri);
        if (destination == LinkDestination.System)
        {
            OpenExternally(e.Uri);
            return;
        }
        // A scripted popup with a size (e.g. "Sign in with Google") needs its opener to report back
        // to, so it stays in the app. Every other link to another site goes to the browser.
        if (destination == LinkDestination.Browser && !e.WindowFeatures.HasSize)
        {
            OpenExternally(e.Uri);
            return;
        }

        // Like browsers: Ctrl+click opens in the background, Ctrl+Shift+click brings it forward.
        var background = NativeMethods.IsControlDown && !NativeMethods.IsShiftDown;
        var deferral = e.GetDeferral();
        try
        {
            var tab = _owner.OpenTab(url: null, after: this, activate: !background);
            await tab.InitializeAsync();
            // Handing over the new tab's engine keeps window.opener working.
            e.NewWindow = tab.Core;
        }
        finally
        {
            deferral.Complete();
        }
    }

    private void OnWebMessageReceived(CoreWebView2 sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        string? message;
        try
        {
            message = e.TryGetWebMessageAsString();
        }
        catch (ArgumentException)
        {
            return;
        }
        if (message?.StartsWith("webappwrap:", StringComparison.Ordinal) == true)
            _owner.RunCommand(message["webappwrap:".Length..]);
    }
}
