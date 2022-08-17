module tui;

import core.sys.posix.termios;
import core.sys.posix.unistd;
import core.sys.posix.sys.ioctl;
import core.stdc.stdio;
import core.stdc.ctype;
import std.signals; // import std.signals : Signal does not work ...
import std.typecons : Tuple;
import std.array : appender;
import std.range : empty, front, popFront, cycle;
import std.exception : errnoEnforce, enforce;
import std.string : join, split, format;
import std.algorithm : countUntil, find, max;
import std.conv : to;
import colored : forceStyle, Style;

alias Position = Tuple!(int, "x", int, "y");
alias Dimension = Tuple!(int, "width", int, "height"); /// https://en.wikipedia.org/wiki/ANSI_escape_code

@safe auto next(Range)(Range r)
{
    r.popFront;
    return r.front;
}

enum Operation : string
{
    CURSOR_UP = "A",
    CURSOR_DOWN = "B",
    CURSOR_FORWARD = "C",
    CURSOR_BACKWARD = "D",
    CURSOR_POSITION = "H",
    ERASE_IN_DISPLAY = "J",
    ERASE_IN_LINE = "K",
    DEVICE_STATUS_REPORT = "n",
    CURSOR_POSITION_REPORT = "R",
    CLEAR_TERMINAL = "2J",
    CLEAR_LINE = "2K",
}

enum State : string
{
    CURSOR = "?25",
    ALTERNATE_BUFFER = "?1049",
}

enum Mode : string
{
    LOW = "l",
    HIGH = "h",
}

string execute(Operation operation)
{
    return "\x1b[" ~ operation;
}

string execute(Operation operation, string[] args...)
{
    return "\x1b[" ~ args.join(";") ~ operation;
}

string to(State state, Mode mode)
{
    return "\x1b[" ~ state ~ mode;
}

Terminal INSTANCE;
class Terminal
{
    termios originalState;
    auto buffer = appender!(char[])();
    this()
    {
        (tcgetattr(1, &originalState) == 0).errnoEnforce("Cannot get termios");

        termios newState = originalState;
        newState.c_lflag &= ~ECHO & ~ICANON;
        (tcsetattr(1, TCSAFLUSH, &newState) == 0).errnoEnforce("Cannot set new termios state");

        wDirect(State.ALTERNATE_BUFFER.to(Mode.HIGH), "Cannot switch to alternate buffer");
        wDirect(Operation.CLEAR_TERMINAL.execute, "Cannot clear terminal");
        wDirect(State.CURSOR.to(Mode.LOW), "Cannot hide cursor");
    }

    ~this()
    {
        wDirect(Operation.CLEAR_TERMINAL.execute, "Cannot clear alternate buffer");
        wDirect(State.ALTERNATE_BUFFER.to(Mode.LOW), "Cannot switch to normal buffer");
        wDirect(State.CURSOR.to(Mode.HIGH), "Cannot show cursor");

        (tcsetattr(1, TCSANOW, &originalState) == 0).errnoEnforce("Cannot set original termios state");
        import std.stdio : writeln; writeln("cleanup done");
    }

    auto putString(string s)
    {
        w(s);
        return this;
    }

    auto xy(int x, int y)
    {
        w(Operation.CURSOR_POSITION.execute((y + 1).to!string, (x + 1)
                .to!string));
        return this;
    }

    final void wDirect(string data, lazy string errorMessage)
    {
        (core.sys.posix.unistd.write(2, data.ptr, data.length) == data.length).errnoEnforce(errorMessage);
    }

    final void w(string data)
    {
        buffer.put(cast(char[]) data);
    }

    auto clear()
    {
        buffer.clear();
        w(Operation.CLEAR_TERMINAL.execute);
        return this;
    }

    auto flip()
    {
        auto data = buffer.data;
        (core.sys.posix.unistd.write(2, data.ptr, data.length) == data.length).errnoEnforce(
                "Cannot blit data");
        return this;
    }


    Dimension dimension()
    {
        winsize ws;
        (ioctl(1, TIOCGWINSZ, &ws) == 0).errnoEnforce("Cannot get winsize");
        return Dimension(ws.ws_col, ws.ws_row);
    }

    immutable(KeyInput) getInput()
    {
        char[3] buffer;
        auto count = core.sys.posix.unistd.read(1, &buffer, buffer.length);
        (count != -1).errnoEnforce("Cannot read next input");
        return KeyInput.fromText(buffer[0 .. count].idup);
    }
}

enum Key : string
{
    up = [27, 91, 65],
    down = [27, 91, 66],
    left = [27, 91, 67],
    right = [27, 91, 68],/+
     codeYes = KEY_CODE_YES,
     min = KEY_MIN,
     codeBreak = KEY_BREAK,
     left = KEY_LEFT,
     right = KEY_RIGHT,
     home = KEY_HOME,
     backspace = KEY_BACKSPACE,
     f0 = KEY_F0,
     f1 = KEY_F(1),
     f2 = KEY_F(2),
     f3 = KEY_F(3),
     f4 = KEY_F(4),
     f5 = KEY_F(5),
     f6 = KEY_F(6),
     f7 = KEY_F(7),
     f8 = KEY_F(8),
     f9 = KEY_F(9),
     f10 = KEY_F(10),
     f11 = KEY_F(11),
     f12 = KEY_F(12),
     f13 = KEY_F(13),
     f14 = KEY_F(14),
     f15 = KEY_F(15),
     f16 = KEY_F(16),
     f17 = KEY_F(17),
     f18 = KEY_F(18),
     f19s = KEY_F(19),
     f20 = KEY_F(20),
     f21 = KEY_F(21),
     f22 = KEY_F(22),
     f23 = KEY_F(23),
     f24 = KEY_F(24),
     f25 = KEY_F(25),
     f26 = KEY_F(26),|
     f27 = KEY_F(27),
     f28 = KEY_F(28),
     f29 = KEY_F(29),
     f30 = KEY_F(30),
     f31 = KEY_F(31),
     f32 = KEY_F(32),
     f33 = KEY_F(33),
     f34 = KEY_F(34),
     f35 = KEY_F(35),
     f36 = KEY_F(36),
     f37 = KEY_F(37),
     f38 = KEY_F(38),
     f39 = KEY_F(39),
     f40 = KEY_F(40),
     f41 = KEY_F(41),
     f42 = KEY_F(42),
     f43 = KEY_F(43),
     f44 = KEY_F(44),
     f45 = KEY_F(45),
     f46 = KEY_F(46),
     f47 = KEY_F(47),
     f48 = KEY_F(48),
     f49 = KEY_F(49),
     f50 = KEY_F(50),
     f51 = KEY_F(51),
     f52 = KEY_F(52),
     f53 = KEY_F(53),
     f54 = KEY_F(54),
     f55 = KEY_F(55),
     f56 = KEY_F(56),
     f57 = KEY_F(57),
     f58 = KEY_F(58),
     f59 = KEY_F(59),
     f60 = KEY_F(60),
     f61 = KEY_F(61),
     f62 = KEY_F(62),
     f63 = KEY_F(63),
     dl = KEY_DL,
     il = KEY_IL,
     dc = KEY_DC,
     ic = KEY_IC,
     eic = KEY_EIC,
     clear = KEY_CLEAR,
     eos = KEY_EOS,
     eol = KEY_EOL,
     sf = KEY_SF,
     sr = KEY_SR,
     npage = KEY_NPAGE,
     ppage = KEY_PPAGE,
     stab = KEY_STAB,
     ctab = KEY_CTAB,
     catab = KEY_CATAB,
     enter = KEY_ENTER,
     sreset = KEY_SRESET,
     reset = KEY_RESET,
     print = KEY_PRINT,
     ll = KEY_LL,
     a1 = KEY_A1,
     a3 = KEY_A3,
     b2 = KEY_B2,
     c1 = KEY_C1,
     c3 = KEY_C3,
     btab = KEY_BTAB,
     beg = KEY_BEG,
     cancel = KEY_CANCEL,
     close = KEY_CLOSE,
     command = KEY_COMMAND,
     copy = KEY_COPY,
     create = KEY_CREATE,
     end = KEY_END,
     exit = KEY_EXIT,
     find = KEY_FIND,
     help = KEY_HELP,
     mark = KEY_MARK,
     message = KEY_MESSAGE,
     move = KEY_MOVE,
     next = KEY_NEXT,
     open = KEY_OPEN,
     options = KEY_OPTIONS,
     previous = KEY_PREVIOUS,
     redo = KEY_REDO,
     reference = KEY_REFERENCE,
     refresh = KEY_REFRESH,
     replace = KEY_REPLACE,
     restart = KEY_RESTART,
     resume = KEY_RESUME,
     save = KEY_SAVE,
     sbeg = KEY_SBEG,
     scancel = KEY_SCANCEL,
     scommand = KEY_SCOMMAND,
     scopy = KEY_SCOPY,
     screate = KEY_SCREATE,
     sdc = KEY_SDC,
     sdl = KEY_SDL,
     select = KEY_SELECT,
     send = KEY_SEND,
     seol = KEY_SEOL,
     sexit = KEY_SEXIT,
     sfind = KEY_SFIND,
     shelp = KEY_SHELP,
     shome = KEY_SHOME,
     sic = KEY_SIC,
     sleft = KEY_SLEFT,
     smessage = KEY_SMESSAGE,
     smove = KEY_SMOVE,
     snext = KEY_SNEXT,
     soptions = KEY_SOPTIONS,
     sprevious = KEY_SPREVIOUS,
     sprint = KEY_SPRINT,
     sredo = KEY_SREDO,
     sreplace = KEY_SREPLACE,
     sright = KEY_SRIGHT,
     srsume = KEY_SRSUME,
     ssave = KEY_SSAVE,
     ssuspend = KEY_SSUSPEND,
     sundo = KEY_SUNDO,
     suspend = KEY_SUSPEND,
     undo = KEY_UNDO,
     mouse = KEY_MOUSE,
     resize = KEY_RESIZE,
     event = KEY_EVENT,
     max = KEY_MAX,
     +/

}
/+
 enum Attributes : chtype
 {
 normal = A_NORMAL,
 charText = A_CHARTEXT,
 color = A_COLOR,
 standout = A_STANDOUT,
 underline = A_UNDERLINE,
 reverse = A_REVERSE,
 blink = A_BLINK,
 dim = A_DIM,
 bold = A_BOLD,
 altCharSet = A_ALTCHARSET,
 invis = A_INVIS,
 protect = A_PROTECT,
 horizontal = A_HORIZONTAL,
 left = A_LEFT,
 low = A_LOW,
 right = A_RIGHT,
 top = A_TOP,
 vertical = A_VERTICAL,
 }

  +/
/// either a special key like arrow or backspace
/// or an utf-8 string (e.g. ä is already 2 bytes in an utf-8 string)
struct KeyInput
{
    static int COUNT = 0;
    int count;
    string input;
    byte[] bytes;
    this(int count, string input)
    {
        this.count = count;
        this.input = input.dup;
    }

    this(int count, byte[] bytes)
    {
        this.count = count;
        this.bytes = bytes;
    }

    static auto fromText(string s)
    {
        return cast(immutable)KeyInput(COUNT++, s);
    }

    static auto fromBytes(byte[] bytes)
    {
        return KeyInput(COUNT++, bytes);
    }
}

class NoKeyException : Exception
{
    this(string s)
    {
        super(s);
    }
}

int byteCount(int k)
{
    if (k < 0b1100_0000)
    {
        return 1;
    }
    if (k < 0b1110_0000)
    {
        return 2;
    }

    if (k > 0b1111_0000)
    {
        return 3;
    }

    return 4;
}

alias InputHandler = bool delegate(KeyInput input);
alias ButtonHandler = void delegate();
abstract class Component
{
    Component parent;
    Component[] children;

    // the root of a component hierarchy carries all focusComponents,
    // atm those have to be registered manually via
    // addToFocusComponents.
    Component focusPath;

    // component that is really focused atm
    Component currentFocusedComponent;
    // stores the focused component in case a popup is pushed
    Component lastFocusedComponent;

    InputHandler inputHandler;

    int left;
    int top;
    int width;
    int height;

    this(Component[] children = null)
    {
        this.children = children;
        foreach (child; children)
        {
            child.setParent(this);
        }
    }

    void clearFocus()
    {
        this.currentFocusedComponent = null;
        foreach (Component c; children)
        {
            c.clearFocus();
        }
    }

    auto setInputHandler(InputHandler inputHandler)
    {
        this.inputHandler = inputHandler;
    }

    void resize(int left, int top, int width, int height)
    {
        this.left = left;
        this.top = top;
        this.width = width;
        this.height = height;
    }

    auto setParent(Component parent)
    {
        this.parent = parent;
    }

    abstract void render(Context context);
    bool handlesInput()
    {
        return true;
    }
    bool focusable() {
        return false;
    }
    bool handleInput(KeyInput input)
    {
        switch (input.input)
        {
        case "\t":
            focusNext();
            return true;
        default:
            if (focusPath !is null && focusPath.handleInput(input))
            {
                return true;
            }
            if (inputHandler !is null && inputHandler(input))
            {
                return true;
            }
            return false;
        }
    }
    // establishes the input handling path from current focused
    // child to the root component
    void requestFocus()
    {
        currentFocusedComponent = this;
        if (this.parent !is null)
        {
            this.parent.buildFocusPath(this, this);
        }
    }

    void buildFocusPath(Component focusedComponent, Component path)
    {
        enforce(children.countUntil(path) >= 0, "Cannot find child");
        this.focusPath = path;
        if (this.currentFocusedComponent !is null)
        {
            this.currentFocusedComponent.currentFocusedComponent = focusedComponent;
        }
        this.currentFocusedComponent = focusedComponent;
        if (this.parent !is null)
        {
            this.parent.buildFocusPath(focusedComponent, this);
        }
    }

    void focusNext()
    {
        if (parent is null)
        {
            auto components = findAllFocusableComponents();
            if (currentFocusedComponent is null) {
                components.front.requestFocus;
            } else {
                components
                    .cycle
                    .find(currentFocusedComponent)
                    .next
                    .requestFocus;
            }
        }
        else
        {
            parent.focusNext();
        }
    }
    private Component[] findAllFocusableComponents(Component[] result=null) {
        if (focusable()) {
            result ~= this;
        }
        foreach (child; children) {
            result = child.findAllFocusableComponents(result);
        }
        return result;
    }
}

class HSplit : Component
{
    int split;
    this(int split, Component top, Component bottom)
    {
        super([top, bottom]);
        this.split = split;
    }

    override void resize(int left, int top, int width, int height)
    {
        super.resize(left, top, width, height);

        int splitPos = split;
        if (split < 0)
        {
            splitPos = height + split;
        }
        this.top.resize(0, 0, width, splitPos);
        this.bottom.resize(0, splitPos, width, height - splitPos);
    }

    override void render(Context context)
    {
        this.top.render(context.forChild(this.top));
        this.bottom.render(context.forChild(this.bottom));
    }

    private Component top()
    {
        return children[0];
    }

    private Component bottom()
    {
        return children[1];
    }
}

class VSplit : Component
{
    int split;
    this(int split, Component left, Component right)
    {
        super([left, right]);
        this.split = split;
    }

    override void resize(int left, int top, int width, int height)
    {
        super.resize(left, top, width, height);

        int splitPos = split;
        if (split < 0)
        {
            splitPos = width + split;
        }
        this.left.resize(0, 0, splitPos, height);
        this.right.resize(splitPos, 0, width - split, height);
    }

    override void render(Context context)
    {
        left.render(context.forChild(left));
        right.render(context.forChild(right));
    }

    private Component left()
    {
        return children[0];
    }

    private Component right()
    {
        return children[1];
    }
}

class Filled : Component
{
    string what;
    this(string what)
    {
        this.what = what;
    }

    override void render(Context context)
    {
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                context.putString(x, y, what);
            }
        }
        context.putString(0, 0, "0");
        context.putString(width - 1, height - 1, "1");
    }

    override bool handlesInput()
    {
        return false;
    }
}

class Text : Component
{
    string content;
    this(string content)
    {
        this.content = content;
    }

    override void render(Context context)
    {
        context.putString(0, 0, content);
    }

    override bool handlesInput()
    {
        return false;
    }
}

class MultilineText : Component {
    string[] lines;
    this(string content) {
        lines = content.split("\n");
    }
    override void render(Context context) {
        foreach (idx, line; lines) {
            context.putString(0, cast(int)idx, line);
        }
    }
    override bool handlesInput() {
        return false;
    }
}

class Button : Component
{
    string text;
    ButtonHandler pressed;
    this(string text, ButtonHandler pressed)
    {
        this.text = text;
        this.pressed = pressed;
    }

    override void render(Context c)
    {
        if (currentFocusedComponent == this)
        {
            c.putString(0, 0, "> " ~ text);
        }
        else
        {
            c.putString(0, 0, "  " ~ text);
        }
    }

    override bool handleInput(KeyInput input)
    {
        switch (input.input)
        {
        case " ":
            pressed();
            return true;
        default:
            return false;
        }
    }
    override bool focusable() {
        return true;
    }
    override string toString()
    {
        return "Button";
    }
}

string dropIgnoreAnsiEscapes(string s, int n)
{
    string result;
    bool inColorAnsiEscape = false;
    int count = 0;

    if (n < 0)
    {
        n = -n;
        result = s;
        for (int i = 0; i < n; ++i)
        {
            result = " " ~ result;
        }
        return result;
    }

    while (!s.empty)
    {
        auto current = s.front;
        if (current == 27)
        {
            inColorAnsiEscape = true;
            result ~= current;
        }
        else
        {
            if (inColorAnsiEscape)
            {
                if (current == 'm')
                {
                    inColorAnsiEscape = false;
                }
                result ~= current;
            }
            else
            {
                if (count >= n)
                {
                    result ~= current;
                }
                count++;
            }
        }
        s.popFront;
    }
    return result;
}

@("dropIgnoreAnsiEscapes/basic") unittest
{
    import unit_threaded;

    "abc".dropIgnoreAnsiEscapes(1).should == "bc";
}

@("dropIgnoreAnsiEscapes/basicWithAnsi") unittest
{
    import unit_threaded;

    "a\033[123mbcdefghijkl".dropIgnoreAnsiEscapes(3).should == "\033[123mdefghijkl";
}

@("dropIgnoreAnsiEscapes/dropAll") unittest
{
    import unit_threaded;

    "abc".dropIgnoreAnsiEscapes(4).should == "";
}

@("dropIgnoreAnsiEscapes/negativeNumber") unittest
{
    import unit_threaded;

    "abc".dropIgnoreAnsiEscapes(-1).should == " abc";
}

string takeIgnoreAnsiEscapes(string s, uint length)
{
    string result;
    uint count = 0;
    bool inColorAnsiEscape = false;
    while (!s.empty)
    {
        auto current = s.front;
        if (current == 27)
        {
            inColorAnsiEscape = true;
            result ~= current;
        }
        else
        {
            if (inColorAnsiEscape)
            {
                result ~= current;
                if (current == 'm')
                {
                    inColorAnsiEscape = false;
                }
            }
            else
            {
                if (count < length)
                {
                    result ~= current;
                    count++;
                }
            }
        }
        s.popFront;
    }
    return result;
}

@("takeIgnoreAnsiEscapes") unittest
{
    import unit_threaded;

    "hello world".takeIgnoreAnsiEscapes(5).should == "hello";
    "he\033[123mllo world\033[0m".takeIgnoreAnsiEscapes(5).should == "he\033[123mllo\033[0m";
    "köstlin".takeIgnoreAnsiEscapes(10).should == "köstlin";
}

class List(T, alias stringTransform) : Component
{
    T[] model;
    struct ScrollInfo
    {
        int selection;
        int offset;
        void up()
        {
            if (selection > 0)
            {
                selection--;
                while (selection < offset)
                {
                    offset--;
                }
            }
        }

        void down(T[] model, int height)
        {
            if (selection + 1 < model.length)
            {
                selection++;
                while (selection >= offset + height)
                {
                    offset++;
                }
            }
        }
    }

    ScrollInfo scrollInfo;
    mixin Signal!(T) selectionChanged;
    this(T[] model)
    {
        this.model = model;
        this.scrollInfo = ScrollInfo(0, 0);
    }
    T[] delegate() getData;
    this(T[] delegate() getData)
    {
        this.getData = getData;
        this.scrollInfo = ScrollInfo(0, 0);
    }

    override void render(Context context)
    {
        if (getData)
        {
            model = getData();
        }
        for (int i = 0; i < height; ++i)
        {
            const index = i + scrollInfo.offset;
            if (index >= model.length)
                return;
            const selected = (index == scrollInfo.selection) && (currentFocusedComponent == this);
            auto text = "%s %s"
                .format(selected ? ">" : " ", stringTransform(model[index]));
            text = selected ? text.forceStyle(Style.reverse) : text;
            context.putString(0, i, text);
        }
    }

    void up()
    {
        if (model.empty)
        {
            return;
        }
        scrollInfo.up;
        selectionChanged.emit(model[scrollInfo.selection]);
    }

    void down()
    {
        if (model.empty)
        {
            return;
        }
        scrollInfo.down(model, height);
        selectionChanged.emit(model[scrollInfo.selection]);
    }

    void select()
    {
        if (model.empty)
        {
            return;
        }
        selectionChanged.emit(model[scrollInfo.selection]);
    }

    auto getSelection()
    {
        return model[scrollInfo.selection];
    }

    override bool handleInput(KeyInput input)
    {
        switch (input.input)
        {
        case "w":
        case "j":
        case Key.up:
            up();
            return true;
        case "s":
        case "k":
        case Key.down:
            down();
            return true;
        default:
            return super.handleInput(input);
        }
    }

    override bool focusable() {
        return true;
    }

    override string toString() {
        return "List";
    }
}

struct Viewport
{
    int x;
    int y;
    int width;
    int height;
}

class ScrollPane : Component
{
    Viewport viewport;
    this(Component child)
    {
        super([child]);
    }

    bool up()
    {
        viewport.y = max(viewport.y -1 , 0);
        return true;
    }

    bool down()
    {
        viewport.y++;
        return true;
    }

    bool left()
    {
        viewport.x++;
        return true;
    }

    bool right()
    {
        viewport.x = max(viewport.x - 1, 0);
        return true;
    }

    override bool handleInput(KeyInput input)
    {
        switch (input.input)
        {
        case "w":
        case "j":
        case Key.up:
            return up();
        case "s":
        case "k":
        case Key.down:
            return down();
        case "a":
        case "h":
        case Key.left:
            return left();
        case "d":
        case "l":
        case Key.right:
            return right();
        default:
            return super.handleInput(input);
        }
    }
    override bool focusable() {
        return true;
    }
    override void render(Context c)
    {
        auto child = children.front;
        child.render(c.forChild(child, viewport));
        if (currentFocusedComponent == this)
        {
            c.putString(0, 0, ">");
        }
    }

    override void resize(int left, int top, int width, int height)
    {
        super.resize(left, top, width, height);
        viewport.width = width;
        viewport.height = height;
        auto child = children.front;
        child.resize(0, 0, 1000, 1000);
    }
}

extern (C) void signal(int sig, void function(int));
UiInterface theUi;
extern (C) void windowSizeChangedSignalHandler(int)
{
    theUi.resized();
}

abstract class UiInterface
{
    void resized();
}

class Context
{
    Terminal terminal;
    int left;
    int top;
    int width;
    int height;
    Viewport viewport;
    this(Terminal terminal, int left, int top, int width, int height)
    {
        this.terminal = terminal;
        this.left = left;
        this.top = top;
        this.width = width;
        this.height = height;
        this.viewport = Viewport(0, 0, width, height);
    }

    this(Terminal terminal, int left, int top, int width, int height, Viewport viewport)
    {
        this.terminal = terminal;
        this.left = left;
        this.top = top;
        this.width = width;
        this.height = height;
        this.viewport = viewport;
    }
    override string toString()
    {
        return "Context(left=%s, top=%s, width=%s, height=%s, viewport=%s)".format(left, top, width, height, viewport);
    }
    auto forChild(Component c)
    {
        return new Context(terminal, this.left + c.left, this.top + c.top, c.width, c.height);
    }

    auto forChild(Component c, Viewport viewport)
    {
        return new Context(terminal, this.left + c.left, this.top + c.top,
                c.width, c.height, viewport);
    }

    auto putString(int x, int y, string s)
    {
        int scrolledY = y - viewport.y;
        if (scrolledY < 0) {
            return this;
        }
        if (scrolledY > viewport.height)
        {
            return this;
        }
        int screenYpos = scrolledY + top;
        terminal.xy(left + x, screenYpos).putString(s.dropIgnoreAnsiEscapes(viewport.x)
                .takeIgnoreAnsiEscapes(viewport.width));
        return this;
    }
}

class Ui : UiInterface
{
    Terminal terminal;
    Component[] roots;
    this(Terminal terminal)
    {
        this.terminal = terminal;
        theUi = this;
        signal(28, &windowSizeChangedSignalHandler);
    }

    auto push(Component root)
    {
        if (!roots.empty)
        {
            auto oldRoot = roots[$ - 1];
            oldRoot.lastFocusedComponent = oldRoot.currentFocusedComponent;
            oldRoot.clearFocus;
        }
        roots ~= root;
        auto dimension = terminal.dimension;
        root.resize(0, 0, dimension.width, dimension.height);
        root.focusNext;
        return this;
    }

    auto pop()
    {
        roots = roots[0 .. $ - 1];

        auto root = roots[$ - 1];
        root.lastFocusedComponent.requestFocus;
        root.lastFocusedComponent = null;
        return this;
    }

    void render()
    {
        try
        {
            terminal.clear;
            foreach (root; roots)
            {
                scope context = new Context(
                    terminal,
                    root.left,
                    root.top,
                    root.width,
                    root.height);
                root.render(context);
            }
            terminal.flip;
        }
        catch (Exception e)
        {
            import std.experimental.logger : error;

            e.to!string.error;
        }
    }

    override void resized()
    {
        auto dimension = terminal.dimension;
        foreach (root; roots)
        {
            root.resize(0, 0, dimension.width, dimension.height);
        }
        render;
    }

    void resize()
    {
        with (terminal.dimension)
        {
            foreach (root; roots)
            {
                root.resize(0, 0, width, height);
            }
        }
    }
    void handleInput(KeyInput input)
    {
        roots[$-1].handleInput(input);
    }
}

struct Refresh
{
}
