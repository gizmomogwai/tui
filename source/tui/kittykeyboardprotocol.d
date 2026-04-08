module tui.kittykeyboardprotocol;
import std.algorithm : map;
import std.array : array;
import std.ascii : ControlChar;
import std.format : format;
import std.range : empty;
import std.string : split;
import std.typecons : tuple;

/// https://sw.kovidgoyal.net/kitty/keyboard-protocol

/// enable all kitty keyboard protocol enhancements
immutable KITTY_KEYBOARD_ENABLE = format!("\x1b[>%du")(0b11111);
/// disable kitty keyboard protocol enhancements
immutable KITTY_KEYBOARD_DISABLE = "\x1b[<u";

class Tokenizer
{
    struct Result
    {
        State state;
        immutable(KeyInput) keyInput;
    }

    abstract class State
    {
        public byte[] all;
        this(byte[] all)
        {
            this.all = all;
        }

        abstract Result feed(byte b);
    }

    class Idle : State
    {
        this()
        {
            super([]);
        }

        override Result feed(byte b)
        {
            if (b == ControlChar.esc)
            {
                return Result(new Escape(this.all ~ b), null);
            }
            return Result(this, null);
        }
    }

    class Escape : State
    {
        this(byte[] all)
        {
            super(all);
        }

        override Result feed(byte b)
        {
            if (b == '[')
            {
                return Result(new CsiReceived(this.all ~ b), null);
            }
            return Result(new Idle, null);
        }
    }

    /// Control Sequence Indicator Received
    class CsiReceived : State
    {
        this(byte[] all)
        {
            super(all);
        }

        override Result feed(byte b)
        {
            if ((b == 'u') || (b >= 'A' && b <= 'Z') || (b == '~'))
            {
                all ~= b;
                return Result(new Idle(), parseKeyInput(all));
            }
            else if ((b >= '0' && b <= '9') || (b == ';') || (b == ':'))
            {
                all ~= b;
                return Result(this, null);
            }
            else
            {
                return Result(new Idle, null);
            }
        }
    }

    State state;
    this()
    {
        state = new Idle();
    }

    auto feed(byte b)
    {
        auto result = state.feed(b);
        state = result.state;
        return result.keyInput;
    }
}

/// https://sw.kovidgoyal.net/kitty/keyboard-protocol/#legacy-functional-keys
enum Modifier : uint
{
    // dfmt off
    none     = 0b0000_0000,
    shift    = 0b0000_0001,
    alt      = 0b0000_0010,
    ctrl     = 0b0000_0100,
    super_   = 0b0000_1000,
    hyper    = 0b0001_0000,
    meta     = 0b0010_0000,
    capsLock = 0b0100_0000,
    numLock  = 0b1000_0000,
    // dfmt on
}

string toString(Modifier m)
{
    string res = "";
    auto add(string s, uint i)
    {
        if ((m & i) != 0)
        {
            if (res.empty)
            {
                res = s;
            }
            else
            {
                res ~= "|";
                res ~= s;
            }
        }
    }

    add("shift", Modifier.shift);
    add("alt", Modifier.alt);
    add("ctrl", Modifier.ctrl);
    add("super", Modifier.super_);
    add("hyper", Modifier.hyper);
    add("meta", Modifier.meta);
    add("caps-lock", Modifier.capsLock);
    add("num-lock", Modifier.numLock);
    return res;
}

Modifier parseModifier(int i)
{
    if ((i == 0) || (i == 1))
    {
        return Modifier.none;
    }

    auto bits = i - 1;
    return cast(Modifier) bits;
}

enum EventType
{
    press = 1,
    repeat = 2,
    release = 3,
}

EventType parseEventType(int i)
{
    switch (i)
    {
    case 1:
        return EventType.press;
    case 2:
        return EventType.repeat;
    case 3:
        return EventType.release;
    default:
        throw new Exception(format("Unknown event type: %s", i));
    }
}

class KeyInput
{
    /// For Key.normal look at the c field
    Key key;
    /// Unicode character
    dchar c;
    Modifier modifiers; /// modifier keys held
    EventType eventType; /// press / repeat / release
    bool ctrlC;
    bool empty;

    static auto fromKey(Key key, Modifier modifiers = Modifier.none,
            EventType eventType = EventType.press)
    {
        KeyInput ki = new KeyInput;
        ki.key = key;
        ki.modifiers = modifiers;
        ki.eventType = eventType;
        return cast(immutable) ki;
    }

    static auto fromPrintable(dchar ch, Modifier modifiers = Modifier.none,
            EventType eventType = EventType.press)
    {
        KeyInput ki = new KeyInput;
        ki.key = Key.normal;
        ki.c = ch;
        ki.modifiers = modifiers;
        ki.eventType = eventType;
        return cast(immutable) ki;
    }

    static auto fromCtrlC()
    {
        KeyInput ki = new KeyInput;
        ki.ctrlC = true;
        return cast(immutable) ki;
    }

    static auto fromInterrupt()
    {
        KeyInput ki = new KeyInput;
        ki.empty = true;
        return cast(immutable) ki;
    }

    static auto fromEmpty()
    {
        KeyInput ki;
        ki.empty = true;
        return cast(immutable) ki;
    }

    override string toString() const
    {
        if (ctrlC)
            return "ctrlC";
        if (empty)
            return "empty";
        if (key == Key.normal)
            return format("c='%s' modifiers=%s eventType=%s", c, modifiers.toString(), eventType);
        return format("key=%s modifiers=%s eventType=%s", key, modifiers.toString(), eventType);
    }
}

private int parseNumber(string s)
{
    uint n = 0;
    int pos = 0;
    while (pos < s.length && s[pos] >= '0' && s[pos] <= '9')
    {
        n = n * 10 + (s[pos++] - '0');
    }
    return n;
}

auto parseModifierAndEvent(string s)
{
    if (s.empty)
    {
        // no modifier -> event = press
        return tuple!("modifiers", "event")(Modifier.none, EventType.press);
    }
    auto parts = s.split(":");
    if (parts.length == 1)
    {
        // only modifier -> event = press
        return tuple!("modifiers", "event")(parseModifier(parseNumber(parts[0])), EventType.press);
    }
    else if (parts.length == 2)
    {
        // modifier and event
        return tuple!("modifiers", "event")(parseModifier(parseNumber(parts[0])),
                parseEventType(parseNumber(parts[1])));
    }
    throw new Exception(format!("cannot parse modifier and event '%s'")(s));
}

immutable(KeyInput) parseKeyInput(const(byte)[] input) @trusted
{
    try
    {
        if (input[0 .. 2] != [27, 91])
        {
            throw new Exception("input does not start with 'esc ['");
        }
        auto parts = input[2 .. $].split(";");
        if (parts.length == 0)
        {
            throw new Exception("Cannot split on ;");
        }
        if (parts.length == 1)
        {
            // no modifiers and events -> press no modifiers
            auto key = kittyStringToKey(cast(string) parts[0]);
            return KeyInput.fromKey(key, Modifier.none, EventType.press);
        }
        else if (parts.length == 2)
        {
            // modifiers and events present
            auto kittyString = parts[0] ~ parts[1][$ - 1];
            auto key = kittyStringToKey(cast(string) kittyString);
            auto modifierAndEvent = parseModifierAndEvent(cast(string) parts[1][0 .. $ - 1]);
            if (key == Key.normal)
            {
                return KeyInput.fromPrintable(cast(dchar) parseNumber(cast(string) parts[0]),
                        modifierAndEvent.modifiers, modifierAndEvent.event);
            }
            return KeyInput.fromKey(key, modifierAndEvent.modifiers, modifierAndEvent.event);
        }
        else if (parts.length == 3)
        {
            // the whole story including keycode, modifier/event and alternate character
            auto kittyString = parts[0] ~ parts[2][$ - 1];
            auto key = kittyStringToKey(cast(string) kittyString);
            auto modifierAndEvent = parseModifierAndEvent(cast(string) parts[1]);
            auto character = parseNumber(cast(string) parts[2][0 .. $ - 1]);
            return KeyInput.fromPrintable(cast(dchar) character,
                    modifierAndEvent.modifiers, modifierAndEvent.event);
        }
        else
        {
            throw new Exception("not 1, 2 or 3 parts");
        }
    }
    catch (Exception e)
    {
        throw new Exception(format!("Cannot parse '%s'")(input), e);
    }
}

/// generated by kbd macro from the table at https://sw.kovidgoyal.net/kitty/keyboard-protocol/#legacy-functional-keys
enum Key
{
    normal,
    escape,
    enter,
    tab,
    backspace,
    insert,
    delete_,
    left,
    right,
    up,
    down,
    page_up,
    page_down,
    home,
    end,
    caps_lock,
    scroll_lock,
    num_lock,
    print_screen,
    pause,
    menu,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    f25,
    f26,
    f27,
    f28,
    f29,
    f30,
    f31,
    f32,
    f33,
    f34,
    f35,
    kp_0,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_decimal,
    kp_divide,
    kp_multiply,
    kp_subtract,
    kp_add,
    kp_enter,
    kp_equal,
    kp_separator,
    kp_left,
    kp_right,
    kp_up,
    kp_down,
    kp_page_up,
    kp_page_down,
    kp_home,
    kp_end,
    kp_insert,
    kp_delete,
    kp_begin,
    media_play,
    media_pause,
    media_play_pause,
    media_reverse,
    media_stop,
    media_fast_forward,
    media_rewind,
    media_track_next,
    media_track_previous,
    media_record,
    lower_volume,
    raise_volume,
    mute_volume,
    left_shift,
    left_control,
    left_alt,
    left_super,
    left_hyper,
    left_meta,
    right_shift,
    right_control,
    right_alt,
    right_super,
    right_hyper,
    right_meta,
    iso_level3_shift,
    iso_level5_shift,
}

/// generated by kbd macro from the table at https://sw.kovidgoyal.net/kitty/keyboard-protocol/#legacy-functional-keys
private Key kittyStringToKey(string s)
{
    switch (s)
    {
    case "27u":
        return Key.escape;
    case "13u":
        return Key.enter;
    case "9u":
        return Key.tab;
    case "127u":
        return Key.backspace;
    case "2~":
        return Key.insert;
    case "3~":
        return Key.delete_;
    case "1D":
    case "D":
        return Key.left;
    case "1C":
    case "C":
        return Key.right;
    case "1A":
    case "A":
        return Key.up;
    case "1B":
    case "B":
        return Key.down;
    case "5~":
        return Key.page_up;
    case "6~":
        return Key.page_down;
    case "1H":
    case "H":
    case "7~":
        return Key.home;
    case "1F":
    case "F":
    case "8~":
        return Key.end;
    case "57358u":
        return Key.caps_lock;
    case "57359u":
        return Key.scroll_lock;
    case "57360u":
        return Key.num_lock;
    case "57361u":
        return Key.print_screen;
    case "57362u":
        return Key.pause;
    case "57363u":
        return Key.menu;
    case "1P":
    case "P":
    case "11~":
        return Key.f1;
    case "1Q":
    case "Q":
    case "12~":
        return Key.f2;
    case "13~":
        return Key.f3;
    case "1S":
    case "14~":
        return Key.f4;
    case "15~":
        return Key.f5;
    case "17~":
        return Key.f6;
    case "18~":
        return Key.f7;
    case "19~":
        return Key.f8;
    case "20~":
        return Key.f9;
    case "21~":
        return Key.f10;
    case "23~":
        return Key.f11;
    case "24~":
        return Key.f12;
    case "57376u":
        return Key.f13;
    case "57377u":
        return Key.f14;
    case "57378u":
        return Key.f15;
    case "57379u":
        return Key.f16;
    case "57380u":
        return Key.f17;
    case "57381u":
        return Key.f18;
    case "57382u":
        return Key.f19;
    case "57383u":
        return Key.f20;
    case "57384u":
        return Key.f21;
    case "57385u":
        return Key.f22;
    case "57386u":
        return Key.f23;
    case "57387u":
        return Key.f24;
    case "57388u":
        return Key.f25;
    case "57389u":
        return Key.f26;
    case "57390u":
        return Key.f27;
    case "57391u":
        return Key.f28;
    case "57392u":
        return Key.f29;
    case "57393u":
        return Key.f30;
    case "57394u":
        return Key.f31;
    case "57395u":
        return Key.f32;
    case "57396u":
        return Key.f33;
    case "57397u":
        return Key.f34;
    case "57398u":
        return Key.f35;
    case "57399u":
        return Key.kp_0;
    case "57400u":
        return Key.kp_1;
    case "57401u":
        return Key.kp_2;
    case "57402u":
        return Key.kp_3;
    case "57403u":
        return Key.kp_4;
    case "57404u":
        return Key.kp_5;
    case "57405u":
        return Key.kp_6;
    case "57406u":
        return Key.kp_7;
    case "57407u":
        return Key.kp_8;
    case "57408u":
        return Key.kp_9;
    case "57409u":
        return Key.kp_decimal;
    case "57410u":
        return Key.kp_divide;
    case "57411u":
        return Key.kp_multiply;
    case "57412u":
        return Key.kp_subtract;
    case "57413u":
        return Key.kp_add;
    case "57414u":
        return Key.kp_enter;
    case "57415u":
        return Key.kp_equal;
    case "57416u":
        return Key.kp_separator;
    case "57417u":
        return Key.kp_left;
    case "57418u":
        return Key.kp_right;
    case "57419u":
        return Key.kp_up;
    case "57420u":
        return Key.kp_down;
    case "57421u":
        return Key.kp_page_up;
    case "57422u":
        return Key.kp_page_down;
    case "57423u":
        return Key.kp_home;
    case "57424u":
        return Key.kp_end;
    case "57425u":
        return Key.kp_insert;
    case "57426u":
        return Key.kp_delete;
    case "1E":
    case "57427~":
        return Key.kp_begin;
    case "57428u":
        return Key.media_play;
    case "57429u":
        return Key.media_pause;
    case "57430u":
        return Key.media_play_pause;
    case "57431u":
        return Key.media_reverse;
    case "57432u":
        return Key.media_stop;
    case "57433u":
        return Key.media_fast_forward;
    case "57434u":
        return Key.media_rewind;
    case "57435u":
        return Key.media_track_next;
    case "57436u":
        return Key.media_track_previous;
    case "57437u":
        return Key.media_record;
    case "57438u":
        return Key.lower_volume;
    case "57439u":
        return Key.raise_volume;
    case "57440u":
        return Key.mute_volume;
    case "57441u":
        return Key.left_shift;
    case "57442u":
        return Key.left_control;
    case "57443u":
        return Key.left_alt;
    case "57444u":
        return Key.left_super;
    case "57445u":
        return Key.left_hyper;
    case "57446u":
        return Key.left_meta;
    case "57447u":
        return Key.right_shift;
    case "57448u":
        return Key.right_control;
    case "57449u":
        return Key.right_alt;
    case "57450u":
        return Key.right_super;
    case "57451u":
        return Key.right_hyper;
    case "57452u":
        return Key.right_meta;
    case "57453u":
        return Key.iso_level3_shift;
    case "57454u":
        return Key.iso_level5_shift;
    default:
        return Key.normal;
    }
}
