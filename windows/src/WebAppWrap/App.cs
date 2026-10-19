using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using WebAppWrap.Browser;
using WebAppWrap.Core;
using WebAppWrap.Generator;

namespace WebAppWrap;

internal sealed class App : Application
{
    public static App? Instance { get; private set; }

    private readonly LaunchOptions _options;
    private DispatcherQueue? _dispatcher;
    private AppConfig? _config;
    private GeneratorWindow? _generator;
    private Task<CoreWebView2Environment>? _webViewEnvironment;

    public App(LaunchOptions options)
    {
        _options = options;
        Instance = this;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Resources.MergedDictionaries.Add(new XamlControlsResources());
        _dispatcher = DispatcherQueue.GetForCurrentThread();

        if (_options.AppId is not { } appId)
        {
            ShowGenerator();
            return;
        }

        _config = AppStore.Load(appId);
        if (_config is null)
        {
            NativeMethods.MessageBox(IntPtr.Zero,
                $"The settings for this app ({appId}) are missing. Recreate it with Web App Wrap.",
                "Web App Wrap", NativeMethods.MbIconError);
            Exit();
            return;
        }
        OpenBrowserWindow();
    }

    /// <summary>The app was launched again while running: open another window, or bring the generator forward.</summary>
    public void OnLaunchedAgain() => _dispatcher?.TryEnqueue(() =>
    {
        if (_config is not null) OpenBrowserWindow();
        else ShowGenerator();
    });

    private void ShowGenerator()
    {
        if (_generator is null)
        {
            _generator = new GeneratorWindow();
            _generator.Closed += (_, _) => _generator = null;
        }
        _generator.Activate();
    }

    public BrowserWindow OpenBrowserWindow(BrowserWindow? cascadeFrom = null)
    {
        var window = new BrowserWindow(_config!, cascadeFrom);
        window.Activate();
        return window;
    }

    /// <summary>
    /// One WebView2 environment for the whole process. Tabs opened by window.open must share it
    /// with their opener, and its user data folder (set in Program.Main) holds this app's sign-ins.
    /// </summary>
    public Task<CoreWebView2Environment> WebViewEnvironment =>
        _webViewEnvironment ??= CoreWebView2Environment
            .CreateWithOptionsAsync(null, AppStore.WebViewDataPath(_config!.Id), new CoreWebView2EnvironmentOptions())
            .AsTask();
}
