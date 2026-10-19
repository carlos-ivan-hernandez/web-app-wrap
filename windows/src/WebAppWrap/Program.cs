using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using WebAppWrap.Core;

namespace WebAppWrap;

/// <summary>How this process was launched.</summary>
internal sealed record LaunchOptions(string? AppId)
{
    /// <summary>"--app &lt;id&gt;" runs a wrapped app; anything else opens the Web App Wrap window.</summary>
    public static LaunchOptions Parse(string[] args)
    {
        var index = Array.IndexOf(args, "--app");
        return new LaunchOptions(index >= 0 && index + 1 < args.Length ? args[index + 1] : null);
    }
}

public static class Program
{
    private const string GeneratorInstanceKey = "com.waw.WebAppWrap";

    [STAThread]
    public static int Main(string[] args)
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        var options = LaunchOptions.Parse(args);

        if (options.AppId is { } appId)
        {
            // Must happen before any window exists, so the taskbar groups this window under the
            // wrapped app's shortcut (and its icon) instead of under WebAppWrap.exe.
            NativeMethods.SetCurrentProcessExplicitAppUserModelID(appId);
            // Each wrapped app keeps its own cookies, storage and sign-ins.
            Environment.SetEnvironmentVariable("WEBVIEW2_USER_DATA_FOLDER", AppStore.WebViewDataPath(appId));
        }

        // One process per wrapped app (and one for the generator). Launching it again, e.g. from
        // the Start menu, opens a new window in the running process instead.
        var instance = AppInstance.FindOrRegisterForKey(options.AppId ?? GeneratorInstanceKey);
        if (!instance.IsCurrent)
        {
            RedirectActivation(instance);
            return 0;
        }
        instance.Activated += (_, _) => App.Instance?.OnLaunchedAgain();

        Application.Start(_ =>
        {
            SynchronizationContext.SetSynchronizationContext(
                new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            new App(options);
        });
        return 0;
    }

    /// <summary>Hands this launch to the running instance and waits until it has been delivered.</summary>
    private static void RedirectActivation(AppInstance target)
    {
        var arguments = AppInstance.GetCurrent().GetActivatedEventArgs();
        var done = NativeMethods.CreateEvent(IntPtr.Zero, manualReset: true, initialState: false, name: null);
        Task.Run(() =>
        {
            target.RedirectActivationToAsync(arguments).AsTask().Wait();
            NativeMethods.SetEvent(done);
        });
        const uint defaultFlags = 0, infinite = 0xFFFFFFFF;
        NativeMethods.CoWaitForMultipleObjects(defaultFlags, infinite, 1, [done], out _);
        NativeMethods.CloseHandle(done);
    }
}
