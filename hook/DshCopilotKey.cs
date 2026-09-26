using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

internal static class Native
{
    public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    // The union must be declared with its largest member (MOUSEINPUT), otherwise
    // Marshal.SizeOf(INPUT) is too small and SendInput rejects every call.
    [StructLayout(LayoutKind.Explicit)]
    public struct INPUTUNION
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT
    {
        public uint type;
        public INPUTUNION u;
    }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    public static uint KeyEvent(ushort vk, bool up)
    {
        INPUT[] inputs = new INPUT[1];
        inputs[0].type = 1; // INPUT_KEYBOARD
        inputs[0].u.ki.wVk = vk;
        inputs[0].u.ki.wScan = 0;
        inputs[0].u.ki.dwFlags = up ? 2u : 0u; // KEYEVENTF_KEYUP
        inputs[0].u.ki.time = 0;
        inputs[0].u.ki.dwExtraInfo = Program.MarkInjected ? (IntPtr)Program.Magic : IntPtr.Zero;
        return SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
    }
}

internal sealed class Config
{
    public int Port = 3080;
    public string Url = "http://127.0.0.1:3080";
    public string Launcher = "";
    public string LogPath = "";
    public string Trigger = "winshift-f23";
    public bool DryRun = false;

    public static Config Load(string path)
    {
        Config c = new Config();
        string dir = Path.GetDirectoryName(path);
        c.Launcher = Path.Combine(dir, "launch-dsh.cmd");
        c.LogPath = Path.Combine(dir, "watcher.log");
        if (!File.Exists(path)) return c;
        foreach (string raw in File.ReadAllLines(path))
        {
            string line = raw.Trim();
            if (line.Length == 0 || line.StartsWith("#") || line.StartsWith(";")) continue;
            int eq = line.IndexOf('=');
            if (eq <= 0) continue;
            string k = line.Substring(0, eq).Trim().ToLowerInvariant();
            string v = line.Substring(eq + 1).Trim();
            if (v.Length == 0) continue;
            if (k == "port") { int p; if (int.TryParse(v, out p)) c.Port = p; }
            else if (k == "url") c.Url = v;
            else if (k == "launcher") c.Launcher = v;
            else if (k == "log") c.LogPath = v;
            else if (k == "trigger") c.Trigger = v.ToLowerInvariant();
            else if (k == "dryrun") c.DryRun = (v == "1" || v.ToLowerInvariant() == "true" || v.ToLowerInvariant() == "yes");
        }
        return c;
    }
}

internal static class Program
{
    public const uint Magic = 0x4453484B; // "DSHK" - marks our own injected events
    public static bool MarkInjected = true;   // simulate-raw clears this so the watcher treats the events as real hardware input
    private const string TriggerEventName = "Local\\DshCopilotKeyTrigger";
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;

    private const uint VK_LWIN = 0x5B;
    private const uint VK_RWIN = 0x5C;
    private const uint VK_F23 = 0x86;
    private const uint VK_LSHIFT = 0xA0;
    private const uint VK_RSHIFT = 0xA1;

    private static Native.LowLevelKeyboardProc _proc;
    private static IntPtr _hook = IntPtr.Zero;
    private static StreamWriter _log;
    private static Config _cfg;
    private static Mutex _mutex;

    // watch state
    private static bool _winDown;
    private static bool _shiftDown;
    private static bool _suppressF23Up;
    private static bool _swallowShiftUp;
    private static bool _swallowWinUp;
    private static DateTime _swallowDeadline = DateTime.MinValue;
    private static DateTime _lastTrigger = DateTime.MinValue;
    private static EventWaitHandle _triggerEvent;

    private static string ExeDir
    {
        get { return Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location); }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        string mode = (args.Length > 0 ? args[0] : "watch").ToLowerInvariant();
        if (mode == "capture") return Capture(args);
        if (mode == "watch") return Watch(args);
        if (mode == "simulate") return Simulate(false);
        if (mode == "simulate-raw") return Simulate(true);
        if (mode == "trigger") return TriggerRemote();
        Console.Error.WriteLine("usage: DshCopilotKey.exe [watch|capture <log> [seconds]|simulate]");
        return 2;
    }

    private static void OpenLog(string path)
    {
        _log = new StreamWriter(new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite), new UTF8Encoding(false));
        _log.AutoFlush = true;
    }

    private static void Log(string message)
    {
        if (_log == null) return;
        try { _log.WriteLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + message); }
        catch { }
    }

    private static bool PortOpen(int port, int timeoutMs)
    {
        try
        {
            using (TcpClient client = new TcpClient())
            {
                IAsyncResult ar = client.BeginConnect("127.0.0.1", port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(timeoutMs)) return false;
                client.EndConnect(ar);
                return true;
            }
        }
        catch { return false; }
    }

    private static int Watch(string[] args)
    {
        bool created;
        _mutex = new Mutex(true, "Local\\DshCopilotKeyWatcher", out created);
        if (!created)
        {
            return 0; // already watching
        }

        _cfg = Config.Load(Path.Combine(ExeDir, "config.ini"));
        OpenLog(_cfg.LogPath);
        Log("=== watcher starting (trigger=" + _cfg.Trigger + ", launcher=" + _cfg.Launcher + ", url=" + _cfg.Url + ") ===");

        Application.ThreadException += delegate(object s, ThreadExceptionEventArgs e) { Log("thread exception: " + e.Exception.Message); };
        AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs e) { Log("fatal: " + e.ExceptionObject); };

        _proc = WatchCallback;
        _hook = Native.SetWindowsHookEx(WH_KEYBOARD_LL, _proc, Native.GetModuleHandle(null), 0);
        if (_hook == IntPtr.Zero)
        {
            Log("ERROR: SetWindowsHookEx failed, win32=" + Marshal.GetLastWin32Error());
            return 3;
        }
        Log("hook installed; press LeftWin+LeftShift+F23 to launch DeepSeek Harness");

        _triggerEvent = new EventWaitHandle(false, EventResetMode.AutoReset, TriggerEventName);
        Thread listener = new Thread(delegate()
        {
            while (true)
            {
                try { _triggerEvent.WaitOne(); Log("external trigger received"); Trigger(); }
                catch (Exception ex) { Log("trigger listener error: " + ex.Message); }
            }
        });
        listener.IsBackground = true;
        listener.Start();

        Application.Run();
        Native.UnhookWindowsHookEx(_hook);
        Log("=== watcher stopped ===");
        return 0;
    }

    private static void Trigger()
    {
        if ((DateTime.Now - _lastTrigger).TotalMilliseconds < 1000) return;
        _lastTrigger = DateTime.Now;
        try { _cfg = Config.Load(Path.Combine(ExeDir, "config.ini")); } catch { }
        Log("Copilot key detected (dryrun=" + _cfg.DryRun + ")");
        if (_cfg.DryRun) { Log("dry-run: not launching anything"); return; }

        try
        {
            if (PortOpen(_cfg.Port, 500))
            {
                Log("web UI already listening on port " + _cfg.Port + " -> opening " + _cfg.Url);
                Process.Start(new ProcessStartInfo(_cfg.Url) { UseShellExecute = true });
                return;
            }

            if (File.Exists(_cfg.Launcher))
            {
                Log("port " + _cfg.Port + " closed -> starting launcher: " + _cfg.Launcher);
                ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/c \"\"" + _cfg.Launcher + "\"\"");
                psi.UseShellExecute = true;
                psi.WorkingDirectory = Path.GetDirectoryName(_cfg.Launcher);
                Process.Start(psi);
                return;
            }

            Log("launcher not found, falling back to npx");
            ProcessStartInfo fb = new ProcessStartInfo("cmd.exe", "/k npx -y @deepseek-ai/dsh@alpha web");
            fb.UseShellExecute = true;
            Process.Start(fb);
        }
        catch (Exception ex)
        {
            Log("launch failed: " + ex.Message);
        }
    }

    private static IntPtr WatchCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        try
        {
            if (nCode >= 0)
            {
                Native.KBDLLHOOKSTRUCT k = (Native.KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(Native.KBDLLHOOKSTRUCT));
                uint msg = (uint)wParam.ToInt64();
                bool isDown = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
                uint vk = k.vkCode;

                // Never react to our own synthetic events (they only release stuck modifiers).
                if (k.dwExtraInfo == (IntPtr)Magic) return Native.CallNextHookEx(_hook, nCode, wParam, lParam);

                if (vk == VK_LWIN || vk == VK_RWIN)
                {
                    if (isDown) { _winDown = true; }
                    else
                    {
                        _winDown = false;
                        if (_swallowWinUp && DateTime.Now <= _swallowDeadline) { _swallowWinUp = false; return (IntPtr)1; }
                        _swallowWinUp = false;
                    }
                }
                else if (vk == VK_LSHIFT || vk == VK_RSHIFT)
                {
                    if (isDown) { _shiftDown = true; }
                    else
                    {
                        _shiftDown = false;
                        if (_swallowShiftUp && DateTime.Now <= _swallowDeadline) { _swallowShiftUp = false; return (IntPtr)1; }
                        _swallowShiftUp = false;
                    }
                }
                else if (vk == VK_F23)
                {
                    if (isDown)
                    {
                        bool combo = _cfg.Trigger == "f23" || (_winDown && _shiftDown);
                        if (combo)
                        {
                            _suppressF23Up = true;
                            _swallowDeadline = DateTime.Now.AddSeconds(3);
                            if (_shiftDown) { Native.KeyEvent((ushort)VK_LSHIFT, true); _swallowShiftUp = true; }
                            if (_winDown) { Native.KeyEvent((ushort)VK_LWIN, true); _swallowWinUp = true; }
                            Trigger();
                            return (IntPtr)1;
                        }
                    }
                    else if (_suppressF23Up)
                    {
                        _suppressF23Up = false;
                        return (IntPtr)1;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Log("hook error: " + ex.Message);
        }
        return Native.CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    private static int TriggerRemote()
    {
        try
        {
            EventWaitHandle ev = EventWaitHandle.OpenExisting(TriggerEventName);
            ev.Set();
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("no running watcher: " + ex.Message);
            return 1;
        }
    }

    private static int Simulate(bool raw)
    {
        MarkInjected = !raw;
        OpenLog(Path.Combine(ExeDir, "simulate.log"));
        Log("simulate: raw=" + raw + " INPUT size=" + Marshal.SizeOf(typeof(Native.INPUT)) + " (x64 expects 40)");
        int failures = 0;
        ushort[] keys = new ushort[] { (ushort)VK_LWIN, (ushort)VK_LSHIFT, (ushort)VK_F23, (ushort)VK_F23, (ushort)VK_LSHIFT, (ushort)VK_LWIN };
        bool[] ups = new bool[] { false, false, false, true, true, true };
        for (int i = 0; i < keys.Length; i++)
        {
            uint sent = Native.KeyEvent(keys[i], ups[i]);
            if (sent != 1) { failures++; Log("  SendInput failed for vk=0x" + keys[i].ToString("X2") + " up=" + ups[i] + " err=" + Marshal.GetLastWin32Error()); }
            Thread.Sleep(40);
        }
        Log("simulate done, failures=" + failures);
        if (_log != null) { _log.Flush(); _log.Dispose(); _log = null; }
        return failures == 0 ? 0 : 1;
    }

    private static int Capture(string[] args)
    {
        string path = args.Length > 1 ? args[1] : Path.Combine(ExeDir, "capture.log");
        int seconds = 900;
        if (args.Length > 2) int.TryParse(args[2], out seconds);
        OpenLog(path);
        Log("# capture started (records only Win-combos, F13-F24 and media/browser/launch keys)");
        _proc = CaptureCallback;
        _hook = Native.SetWindowsHookEx(WH_KEYBOARD_LL, _proc, Native.GetModuleHandle(null), 0);
        if (_hook == IntPtr.Zero) { Log("# ERROR SetWindowsHookEx failed: " + Marshal.GetLastWin32Error()); return 3; }
        Log("# hook installed for " + seconds + "s");
        if (seconds > 0) new System.Threading.Timer(delegate(object o) { Application.ExitThread(); }, null, seconds * 1000, Timeout.Infinite);
        Application.Run();
        Native.UnhookWindowsHookEx(_hook);
        Log("# capture stopped");
        return 0;
    }

    private static bool Down(int vk) { return (Native.GetAsyncKeyState(vk) & 0x8000) != 0; }

    private static bool Interesting(uint vk, uint flags, bool winDown, bool shiftDown)
    {
        if (winDown) return true;
        if (vk >= 0x7C && vk <= 0x87) return true;
        if (vk >= 0xA6 && vk <= 0xFF) return true;
        if (vk == 0x00 || vk == 0xFF || vk == 0xE8) return true;
        if (shiftDown && vk >= 0x7C) return true;
        return false;
    }

    private static IntPtr CaptureCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        try
        {
            if (nCode >= 0)
            {
                Native.KBDLLHOOKSTRUCT k = (Native.KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(Native.KBDLLHOOKSTRUCT));
                uint msg = (uint)wParam.ToInt64();
                bool isDown = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
                bool isUp = msg == WM_KEYUP || msg == WM_SYSKEYUP;
                bool winDown = Down(0x5B) || Down(0x5C) || k.vkCode == 0x5B || k.vkCode == 0x5C;
                bool shiftDown = Down(0xA0) || Down(0xA1) || k.vkCode == 0xA0 || k.vkCode == 0xA1;
                if ((isDown || isUp) && Interesting(k.vkCode, k.flags, winDown, shiftDown))
                {
                    StringBuilder sb = new StringBuilder();
                    sb.Append("event=").Append(isDown ? "DOWN" : "UP");
                    sb.Append(" vk=0x").Append(k.vkCode.ToString("X2"));
                    sb.Append(" scan=0x").Append(k.scanCode.ToString("X2"));
                    sb.Append(" ext=").Append(((k.flags & 0x01) != 0) ? 1 : 0);
                    sb.Append(" injected=").Append(((k.flags & 0x10) != 0) ? 1 : 0);
                    sb.Append(" mods=");
                    sb.Append(Down(0x5B) ? "LWIN " : "");
                    sb.Append(Down(0xA0) ? "LSHIFT " : "");
                    sb.Append(Down(0xA2) ? "LCTRL " : "");
                    sb.Append(Down(0xA4) ? "LALT " : "");
                    Log(sb.ToString());
                }
            }
        }
        catch { }
        return Native.CallNextHookEx(_hook, nCode, wParam, lParam);
    }
}
