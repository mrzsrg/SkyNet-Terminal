using System; using System.Runtime.InteropServices;
public static class SkyCine {
    [StructLayout(LayoutKind.Sequential)] public struct COORD{public short X;public short Y;}
    [StructLayout(LayoutKind.Sequential)] public struct CONSOLE_FONT_INFO_EX{public uint cbSize;public uint nFont;public COORD dwFontSize;public uint FontWeight;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=40)]public string FaceName;}
    [DllImport("kernel32.dll",SetLastError=true)]private static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll",SetLastError=true)]private static extern bool GetCurrentConsoleFontEx(IntPtr h,bool m,ref CONSOLE_FONT_INFO_EX f);
    [DllImport("kernel32.dll",SetLastError=true)]private static extern bool SetCurrentConsoleFontEx(IntPtr h,bool m,ref CONSOLE_FONT_INFO_EX f);
    public static CONSOLE_FONT_INFO_EX NewFont(){CONSOLE_FONT_INFO_EX f=new CONSOLE_FONT_INFO_EX();f.cbSize=(uint)Marshal.SizeOf<CONSOLE_FONT_INFO_EX>();return f;}
    public static bool SetFont(string fn,short ht,short wt){CONSOLE_FONT_INFO_EX f=NewFont();f.dwFontSize=new COORD{X=0,Y=ht};f.FontWeight=(uint)wt;f.FaceName=fn;return SetCurrentConsoleFontEx(GetStdHandle(-11),false,ref f);}
    public static int CellWidth(){CONSOLE_FONT_INFO_EX f=NewFont();if(!GetCurrentConsoleFontEx(GetStdHandle(-11),false,ref f))return 0;return f.dwFontSize.X;}
    public static int CellHeight(){CONSOLE_FONT_INFO_EX f=NewFont();if(!GetCurrentConsoleFontEx(GetStdHandle(-11),false,ref f))return 0;return f.dwFontSize.Y;}
}