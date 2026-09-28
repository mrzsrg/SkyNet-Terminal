using System; using System.Runtime.InteropServices;
public static class SkyNetVt {
    [DllImport("kernel32.dll",SetLastError=true)] private static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll",SetLastError=true)] private static extern bool GetConsoleMode(IntPtr h,out uint m);
    [DllImport("kernel32.dll",SetLastError=true)] private static extern bool SetConsoleMode(IntPtr h,uint m);
    public static bool Enable() { IntPtr h=GetStdHandle(-11); uint m;if(!GetConsoleMode(h,out m))return false; return SetConsoleMode(h,m|0x0004); }
}