using System;
using System.Management.Automation;
using System.Runtime.InteropServices;
using System.Threading;

namespace TerminalAI.Aot;

public static class AotClipboard
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalUnlock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalFree(IntPtr hMem);

    private const uint CF_UNICODETEXT = 13;
    private const uint GMEM_MOVEABLE = 0x0002;

    public static bool SetText(string text, SessionState? sessionState = null)
    {
        if (string.IsNullOrEmpty(text)) return false;

        // 1. Direct Win32 clipboard API (P/Invoke)
        try
        {
            if (SetTextWin32(text))
            {
                return true;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[AotClipboard.SetTextWin32] Direct Win32 clipboard failed: {ex.Message}");
        }

        // 2. Safe PowerShell parameter invocation fallback (no script block strings)
        try
        {
            if (sessionState != null)
            {
                using var ps = PowerShell.Create(RunspaceMode.CurrentRunspace);
                ps.AddCommand("Set-Clipboard").AddParameter("Value", text);
                ps.Invoke();
                return !ps.HadErrors;
            }
            else
            {
                using var ps = PowerShell.Create();
                ps.AddCommand("Set-Clipboard").AddParameter("Value", text);
                ps.Invoke();
                return !ps.HadErrors;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[AotClipboard.SetTextFallback] PowerShell Set-Clipboard failed: {ex.Message}");
        }

        return false;
    }

    private static bool SetTextWin32(string text)
    {
        bool opened = false;
        for (int i = 0; i < 5; i++)
        {
            if (OpenClipboard(IntPtr.Zero))
            {
                opened = true;
                break;
            }
            Thread.Sleep(20);
        }
        if (!opened) return false;

        try
        {
            EmptyClipboard();
            int byteCount = (text.Length + 1) * 2;
            IntPtr hGlobal = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)byteCount);
            if (hGlobal == IntPtr.Zero) return false;

            IntPtr target = GlobalLock(hGlobal);
            if (target == IntPtr.Zero)
            {
                GlobalFree(hGlobal);
                return false;
            }

            try
            {
                Marshal.Copy(text.ToCharArray(), 0, target, text.Length);
                Marshal.WriteInt16(target, text.Length * 2, 0);
            }
            finally
            {
                GlobalUnlock(hGlobal);
            }

            if (SetClipboardData(CF_UNICODETEXT, hGlobal) == IntPtr.Zero)
            {
                GlobalFree(hGlobal);
                return false;
            }

            return true;
        }
        finally
        {
            CloseClipboard();
        }
    }
}
