using System;
using System.Runtime.InteropServices;

// SkyWin — Win32-помощник: полноэкранное окно консоли, размеры окна и экрана.
// Используется стартером Core/start_skynet_fullscreen.ps1 и модулем SkyNet.Anim.
public static class SkyWin
{
    [StructLayout(LayoutKind.Sequential)]
    public struct COORD { public short X; public short Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct SMALL_RECT { public short Left; public short Top; public short Right; public short Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct CONSOLE_SCREEN_BUFFER_INFO
    {
        public COORD dwSize;
        public COORD dwCursorPosition;
        public ushort wAttributes;
        public SMALL_RECT srWindow;
        public COORD dwMaximumWindowSize;
    }

    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GetConsoleScreenBufferInfo(IntPtr h, out CONSOLE_SCREEN_BUFFER_INFO info);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool SetConsoleScreenBufferSize(IntPtr h, COORD size);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool SetConsoleWindowInfo(IntPtr h, bool absolute, ref SMALL_RECT rect);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int nIndex);

    private const int SW_MAXIMIZE = 3;
    private const int SM_CXSCREEN = 0;
    private const int SM_CYSCREEN = 1;

    public static bool HasConsole() { try { return GetConsoleWindow() != IntPtr.Zero; } catch { return false; } }
    public static void Maximize() { try { ShowWindow(GetConsoleWindow(), SW_MAXIMIZE); } catch { } }
    public static int ScreenWidth() { return GetSystemMetrics(SM_CXSCREEN); }
    public static int ScreenHeight() { return GetSystemMetrics(SM_CYSCREEN); }

    /// Меню/заголовок убирать не пытаемся: максимизация + раскрытие буфера дают
    /// полноэкранный вид в conhost, а в Windows Terminal окно разворачивает wt.exe.
    public static void Fullscreen()
    {
        try
        {
            IntPtr hwnd = GetConsoleWindow();
            if (hwnd == IntPtr.Zero) { return; }
            SetWindowPos(hwnd, IntPtr.Zero, 0, 0, ScreenWidth(), ScreenHeight(), 0x0040);
            ShowWindow(hwnd, SW_MAXIMIZE);
        }
        catch { }
    }

    public static int[] ConsoleSize()
    {
        var info = new CONSOLE_SCREEN_BUFFER_INFO();
        if (!GetConsoleScreenBufferInfo(GetStdHandle(-11), out info)) { return new int[] { 0, 0 }; }
        return new int[] { info.srWindow.Right - info.srWindow.Left + 1, info.srWindow.Bottom - info.srWindow.Top + 1 };
    }

    public static int[] BufferSize()
    {
        var info = new CONSOLE_SCREEN_BUFFER_INFO();
        if (!GetConsoleScreenBufferInfo(GetStdHandle(-11), out info)) { return new int[] { 0, 0 }; }
        return new int[] { info.dwSize.X, info.dwSize.Y };
    }

    /// Раскрыть окно и буфер на весь экран (conhost). В Windows Terminal вернёт false.
    public static bool Resize(int cols, int rows)
    {
        if (cols < 20 || rows < 5) { return false; }
        IntPtr h = GetStdHandle(-11);
        var info = new CONSOLE_SCREEN_BUFFER_INFO();
        if (!GetConsoleScreenBufferInfo(h, out info)) { return false; }

        short c = (short)cols;
        short r = (short)rows;
        var window = new SMALL_RECT { Left = 0, Top = 0, Right = (short)(c - 1), Bottom = (short)(r - 1) };
        bool ok = SetConsoleWindowInfo(h, true, ref window);
        var buffer = new COORD { X = c, Y = r };
        if (!SetConsoleScreenBufferSize(h, buffer)) { ok = false; }
        if (!SetConsoleWindowInfo(h, true, ref window)) { ok = false; }
        return ok;
    }
}
