#pragma warning disable CA1050

using Godot;
using SharpHook;
using SharpHook.Data;
using System.Collections.Generic;
using System.Threading.Tasks;

public partial class GlobalInputCSharp : Node
{
    #region Setup
    readonly SimpleGlobalHook _hook = new(GlobalHookType.Keyboard);
    static readonly Dictionary<KeyCode, Key> _hKeyToGodotKey = new()
    {
        {KeyCode.VcUndefined, Key.None},

        {KeyCode.VcEscape, Key.Escape},
        {KeyCode.VcF1, Key.F1},
        {KeyCode.VcF2, Key.F2},
        {KeyCode.VcF3, Key.F3},
        {KeyCode.VcF4, Key.F4},
        {KeyCode.VcF5, Key.F5},
        {KeyCode.VcF6, Key.F6},
        {KeyCode.VcF7, Key.F7},
        {KeyCode.VcF8, Key.F8},
        {KeyCode.VcF9, Key.F9},
        {KeyCode.VcF10, Key.F10},
        {KeyCode.VcF11, Key.F11},
        {KeyCode.VcF12, Key.F12},
        {KeyCode.VcF13, Key.F13},
        {KeyCode.VcF14, Key.F14},
        {KeyCode.VcF15, Key.F15},
        {KeyCode.VcF16, Key.F16},
        {KeyCode.VcF17, Key.F17},
        {KeyCode.VcF18, Key.F18},
        {KeyCode.VcF19, Key.F19},
        {KeyCode.VcF20, Key.F20},
        {KeyCode.VcF21, Key.F21},
        {KeyCode.VcF22, Key.F22},
        {KeyCode.VcF23, Key.F23},
        {KeyCode.VcF24, Key.F24},

        {KeyCode.VcBackQuote, Key.Quoteleft},
        {KeyCode.Vc0, Key.Key0},
        {KeyCode.Vc1, Key.Key1},
        {KeyCode.Vc2, Key.Key2},
        {KeyCode.Vc3, Key.Key3},
        {KeyCode.Vc4, Key.Key4},
        {KeyCode.Vc5, Key.Key5},
        {KeyCode.Vc6, Key.Key6},
        {KeyCode.Vc7, Key.Key7},
        {KeyCode.Vc8, Key.Key8},
        {KeyCode.Vc9, Key.Key9},
        {KeyCode.VcMinus, Key.Minus},
        {KeyCode.VcEquals, Key.Equal},
        {KeyCode.VcBackspace, Key.Backspace},

        {KeyCode.VcTab, Key.Tab},
        {KeyCode.VcCapsLock, Key.Capslock},

        {KeyCode.VcA, Key.A},
        {KeyCode.VcB, Key.B},
        {KeyCode.VcC, Key.C},
        {KeyCode.VcD, Key.D},
        {KeyCode.VcE, Key.E},
        {KeyCode.VcF, Key.F},
        {KeyCode.VcG, Key.G},
        {KeyCode.VcH, Key.H},
        {KeyCode.VcI, Key.I},
        {KeyCode.VcJ, Key.J},
        {KeyCode.VcK, Key.K},
        {KeyCode.VcL, Key.L},
        {KeyCode.VcM, Key.M},
        {KeyCode.VcN, Key.N},
        {KeyCode.VcO, Key.O},
        {KeyCode.VcP, Key.P},
        {KeyCode.VcQ, Key.Q},
        {KeyCode.VcR, Key.R},
        {KeyCode.VcS, Key.S},
        {KeyCode.VcT, Key.T},
        {KeyCode.VcU, Key.U},
        {KeyCode.VcV, Key.V},
        {KeyCode.VcW, Key.W},
        {KeyCode.VcX, Key.X},
        {KeyCode.VcY, Key.Y},
        {KeyCode.VcZ, Key.Z},

        {KeyCode.VcOpenBracket, Key.Bracketleft},
        {KeyCode.VcCloseBracket, Key.Bracketright},
        {KeyCode.VcBackslash, Key.Backslash},
        {KeyCode.VcSemicolon, Key.Semicolon},
        {KeyCode.VcQuote, Key.Apostrophe},
        {KeyCode.VcEnter, Key.Enter},
        {KeyCode.VcComma, Key.Comma},
        {KeyCode.VcPeriod, Key.Period},
        {KeyCode.VcSlash, Key.Slash},
        {KeyCode.VcSpace, Key.Space},

        {KeyCode.VcPrintScreen, Key.Print},
        {KeyCode.VcInsert, Key.Insert},
        {KeyCode.VcHome, Key.Home},
        {KeyCode.VcPageUp, Key.Pageup},
        {KeyCode.VcDelete, Key.Delete},
        {KeyCode.VcEnd, Key.End},
        {KeyCode.VcPageDown, Key.Pagedown},

        {KeyCode.VcDown, Key.Down},
        {KeyCode.VcUp, Key.Up},
        {KeyCode.VcRight, Key.Right},
        {KeyCode.VcLeft, Key.Left},

        {KeyCode.VcNumLock, Key.Numlock},
        {KeyCode.VcNumPad0, Key.Kp0},
        {KeyCode.VcNumPad1, Key.Kp1},
        {KeyCode.VcNumPad2, Key.Kp2},
        {KeyCode.VcNumPad3, Key.Kp3},
        {KeyCode.VcNumPad4, Key.Kp4},
        {KeyCode.VcNumPad5, Key.Kp5},
        {KeyCode.VcNumPad6, Key.Kp6},
        {KeyCode.VcNumPad7, Key.Kp7},
        {KeyCode.VcNumPad8, Key.Kp8},
        {KeyCode.VcNumPad9, Key.Kp9},
        {KeyCode.VcNumPadDivide, Key.KpDivide},
        {KeyCode.VcNumPadMultiply, Key.KpMultiply},
        {KeyCode.VcNumPadSubtract, Key.KpSubtract},
        {KeyCode.VcNumPadAdd, Key.KpAdd},
        {KeyCode.VcNumPadDecimal, Key.KpPeriod},
        {KeyCode.VcNumPadEnter, Key.KpEnter},

        {KeyCode.VcLeftShift, Key.Shift},
        {KeyCode.VcRightShift, Key.Shift},
        {KeyCode.VcLeftControl, Key.Ctrl},
        {KeyCode.VcRightControl, Key.Ctrl},
        {KeyCode.VcLeftAlt, Key.Alt},
        {KeyCode.VcRightAlt, Key.Alt},
        {KeyCode.VcLeftMeta, Key.Meta},
        {KeyCode.VcRightMeta, Key.Meta},
    };
    #endregion

    #region Signals
    private HashSet<Key> _allowedKeys = new();
    private readonly HashSet<KeyCode> _hookKeysDown = new();
    private volatile bool _applicationFocused;

    public void SetAllowedKeys(Godot.Collections.Array keys)
    {
        HashSet<Key> allowed = new();
        if (keys != null)
        {
            foreach (Variant v in keys)
            {
                int value = v.AsInt32();
                if (value > (int)Key.None)
                    allowed.Add((Key)value);
            }
        }
        _allowedKeys = allowed;
    }

    void OnHookKeyPressed(object _, KeyboardHookEventArgs args)
    {
        if (_hookKeysDown.Add(args.Data.KeyCode))
            QueueKey(args, true);
    }

    void OnHookKeyReleased(object _, KeyboardHookEventArgs args)
    {
        _hookKeysDown.Remove(args.Data.KeyCode);
        QueueKey(args, false);
    }

    void QueueKey(KeyboardHookEventArgs args, bool pressed)
    {
        if (_applicationFocused)
            return;
        if (!_hKeyToGodotKey.TryGetValue(args.Data.KeyCode, out Key physical) || physical == Key.None)
            return;
        EventMask modifiers = args.RawEvent.Mask;
        Callable.From(() => DispatchKey(physical, modifiers, pressed)).CallDeferred();
    }

    void DispatchKey(Key physical, EventMask modifiers, bool pressed)
    {
        if (_applicationFocused || !IsInsideTree())
            return;

        Key logical = DisplayServer.KeyboardGetKeycodeFromPhysical(physical);
        if (logical == Key.None)
            logical = physical;
        Key label = DisplayServer.KeyboardGetLabelFromPhysical(physical);
        bool isModifier = physical is Key.Shift or Key.Ctrl or Key.Alt or Key.Meta;
        if (!isModifier && !_allowedKeys.Contains(physical) &&
            !_allowedKeys.Contains(logical) && !_allowedKeys.Contains(label) &&
            (pressed || !Input.IsPhysicalKeyPressed(physical)))
            return;

        using var input = new InputEventKey
        {
            Keycode = logical,
            PhysicalKeycode = physical,
            KeyLabel = label,
            Pressed = pressed,
            ShiftPressed = physical != Key.Shift && (modifiers & EventMask.Shift) != 0,
            CtrlPressed = physical != Key.Ctrl && (modifiers & EventMask.Ctrl) != 0,
            AltPressed = physical != Key.Alt && (modifiers & EventMask.Alt) != 0,
            MetaPressed = physical != Key.Meta && (modifiers & EventMask.Meta) != 0,
        };
        Input.ParseInputEvent(input);
    }
    #endregion

    public override void _Ready()
    {
        _applicationFocused = GetWindow().HasFocus();
        _hook.KeyPressed += OnHookKeyPressed;
        _hook.KeyReleased += OnHookKeyReleased;
        _hook.RunAsync().ContinueWith(
            t => GD.PushError("Global input hook failed to start: " + t.Exception?.GetBaseException().Message),
            TaskContinuationOptions.OnlyOnFaulted);
    }

    public override void _Notification(int what)
    {
        if (what == NotificationApplicationFocusIn)
            _applicationFocused = true;
        else if (what == NotificationApplicationFocusOut)
            _applicationFocused = false;
    }

    public override void _ExitTree()
    {
        if (_hook.IsRunning)
        {
            _hook.Dispose();
        }
    }
}
