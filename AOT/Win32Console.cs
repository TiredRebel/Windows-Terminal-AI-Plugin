using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace TerminalAI.Aot;

public static class Win32Console
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKey(uint uCode, uint uMapType);

    private const byte VK_CONTROL = 0x11;
    private const byte VK_V = 0x56;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    public static void DelayedPaste(int delayMs = 200)
    {
        Task.Run(() =>
        {
            try
            {
                Thread.Sleep(delayMs);
                byte scanCtrl = (byte)MapVirtualKey(VK_CONTROL, 0);
                byte scanV = (byte)MapVirtualKey(VK_V, 0);

                keybd_event(VK_CONTROL, scanCtrl, 0, UIntPtr.Zero);
                keybd_event(VK_V, scanV, 0, UIntPtr.Zero);
                keybd_event(VK_V, scanV, KEYEVENTF_KEYUP, UIntPtr.Zero);
                keybd_event(VK_CONTROL, scanCtrl, KEYEVENTF_KEYUP, UIntPtr.Zero);
            }
            catch { }
        });
    }

    public static MenuAction ReadMenuAction()
    {
        while (true)
        {
            var keyInfo = Console.ReadKey(true);
            var k = keyInfo.Key;
            var ch = keyInfo.KeyChar;
            var ctrl = (keyInfo.Modifiers & ConsoleModifiers.Control) != 0;
            var alt = (keyInfo.Modifiers & ConsoleModifiers.Alt) != 0;

            if ((ctrl && k == ConsoleKey.C) || (int)ch == 3 || k == ConsoleKey.Escape || (int)ch == 27)
                return MenuAction.Cancel;

            if (k == ConsoleKey.Enter || ch == '\r' || ch == '\n')
                return MenuAction.Execute;

            if (!ctrl && !alt)
            {
                if (k == ConsoleKey.C || ch is 'c' or 'C' or 'с' or 'С')
                    return MenuAction.Copy;

                if (k == ConsoleKey.I || ch is 'i' or 'I' or 'і' or 'І' or 'ш' or 'Ш')
                    return MenuAction.Insert;

                if (k == ConsoleKey.X || ch is 'x' or 'X' or 'х' or 'Х' or 'ч' or 'Ч')
                    return MenuAction.Explain;

                if (k == ConsoleKey.A || ch is 'a' or 'A' or 'а' or 'А' or 'ф' or 'Ф')
                    return MenuAction.Ask;
            }
        }
    }
}

public enum MenuAction
{
    Execute,
    Copy,
    Insert,
    Explain,
    Ask,
    Cancel
}
