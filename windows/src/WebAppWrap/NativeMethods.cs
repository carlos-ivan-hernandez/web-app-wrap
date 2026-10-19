using System.Runtime.InteropServices;

namespace WebAppWrap;

internal static partial class NativeMethods
{
    /// <summary>Gives this process a wrapped app's taskbar identity, matching its shortcut.</summary>
    [LibraryImport("shell32.dll", StringMarshalling = StringMarshalling.Utf16)]
    internal static partial int SetCurrentProcessExplicitAppUserModelID(string appId);

    [LibraryImport("user32.dll")]
    private static partial short GetAsyncKeyState(int virtualKey);

    private const int VkShift = 0x10, VkControl = 0x11;

    internal static bool IsControlDown => (GetAsyncKeyState(VkControl) & 0x8000) != 0;
    internal static bool IsShiftDown => (GetAsyncKeyState(VkShift) & 0x8000) != 0;

    [LibraryImport("user32.dll")]
    internal static partial uint GetDpiForWindow(IntPtr hwnd);

    [LibraryImport("user32.dll", EntryPoint = "MessageBoxW", StringMarshalling = StringMarshalling.Utf16)]
    internal static partial int MessageBox(IntPtr owner, string text, string caption, uint type);

    internal const uint MbIconError = 0x10;

    // Used to wait for activation redirection without blocking the STA thread's COM calls.
    [LibraryImport("kernel32.dll", EntryPoint = "CreateEventW", StringMarshalling = StringMarshalling.Utf16)]
    internal static partial IntPtr CreateEvent(IntPtr attributes, [MarshalAs(UnmanagedType.Bool)] bool manualReset, [MarshalAs(UnmanagedType.Bool)] bool initialState, string? name);

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool SetEvent(IntPtr handle);

    [LibraryImport("ole32.dll")]
    internal static partial uint CoWaitForMultipleObjects(uint flags, uint timeout, uint count, [In] IntPtr[] handles, out uint index);

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool CloseHandle(IntPtr handle);
}
