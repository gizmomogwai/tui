module tui;

import core.sys.posix.signal : SIGINT;
import core.sys.posix.sys.ioctl : ioctl, TIOCGWINSZ, winsize;
import core.sys.posix.termios : ECHO, ICANON, tcgetattr, TCSAFLUSH, TCSANOW, tcsetattr, termios;
import std.algorithm : countUntil, find, max, min;
import std.array : appender, array;
import std.conv : to;
import std.exception : enforce, errnoEnforce;
import std.math.algebraic : abs;
import std.range : cycle, empty, front, popFront, split;
import std.string : format, join;
import std.typecons : Tuple;
import tui.kittykeyboardprotocol : Tokenizer;
public import tui.kittykeyboardprotocol : KeyInput, KITTY_KEYBOARD_DISABLE,
    KITTY_KEYBOARD_ENABLE, Key, Modifier, EventType;

version (unittest)
{
    import unit_threaded;
}

alias Position = Tuple!(int, "x", int, "y");
alias Dimension = Tuple!(int, "width", int, "height"); /// https://en.wikipedia.org/wiki/ANSI_escape_code
enum SIGWINCH = 28;
@safe auto next(Range)(Range r)
{
    r.popFront;
    return r.front;
}

@("next") unittest
{
    auto range = [1, 2, 3];
    range.next.should == 2;
    range.next.should == 2;
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

string execute(Operation operation, string[] args...)
{
    return "\x1b[" ~ args.join(";") ~ operation;
}

string to(State state, Mode mode)
{
    return "\x1b[" ~ state ~ mode;
}

__gshared Terminal INSTANCE;

extern (C) void signal(int sig, void function(int));
extern (C) void ctrlC(int s)
{
    import core.sys.posix.unistd : write;

    INSTANCE.ctrlCSignalFD().write(&s, s.sizeof);
}

class SelectSet
{
    import core.stdc.errno : EINTR, errno;
    import core.sys.posix.sys.select : FD_ISSET, FD_SET, fd_set, FD_ZERO, select;

    fd_set fds;
    int maxFD;
    this()
    {
        FD_ZERO(&fds);
        maxFD = 0;
    }

    void addFD(int fd)
    {
        FD_SET(fd, &fds);
        maxFD = max(fd, maxFD);
    }

    int readyForRead()
    {
        return select(maxFD + 1, &fds, null, null, null);
    }

    bool isSet(int fd)
    {
        return FD_ISSET(fd, &fds);
    }
}

class Terminal
{
    int stdinFD;
    int stdoutFD;
    termios originalState;
    auto buffer = appender!(char[])();
    /// used to handle signals
    int[2] selfSignalFDs;
    int ctrlCSignalFD()
    {
        return selfSignalFDs[1];
    }

    /// used to run delegates in the input handling thread
    int[2] terminalThreadFDs;
    void delegate()[] terminalThreadDelegates;

    this(int stdinFD = 0, int stdoutFD = 1)
    {
        import core.sys.posix.unistd : pipe;

        auto result = pipe(this.selfSignalFDs);
        (result != -1).errnoEnforce("Cannot create pipe for signal handling");

        result = pipe(this.terminalThreadFDs);
        (result != -1).errnoEnforce("Cannot create pipe for run in terminal input thread");

        this.stdinFD = stdinFD;
        this.stdoutFD = stdoutFD;

        (tcgetattr(stdoutFD, &originalState) == 0).errnoEnforce("Cannot get termios");

        termios newState = originalState;
        newState.c_lflag &= ~ECHO & ~ICANON;
        (tcsetattr(stdoutFD, TCSAFLUSH, &newState) == 0).errnoEnforce(
                "Cannot set new termios state");

        wDirect(State.ALTERNATE_BUFFER.to(Mode.HIGH), "Cannot switch to alternate buffer");
        wDirect(Operation.CLEAR_TERMINAL.execute, "Cannot clear terminal");
        wDirect(State.CURSOR.to(Mode.LOW), "Cannot hide cursor");
        wDirect(KITTY_KEYBOARD_ENABLE, "Cannot enable kitty keyboard protocol");

        INSTANCE = this;
        2.signal(&ctrlC);
    }

    ~this()
    {
        wDirect(KITTY_KEYBOARD_DISABLE, "Cannot disable kitty keyboard protocol");
        wDirect(Operation.CLEAR_TERMINAL.execute, "Cannot clear alternate buffer");
        wDirect(State.ALTERNATE_BUFFER.to(Mode.LOW), "Cannot switch to normal buffer");
        wDirect(State.CURSOR.to(Mode.HIGH), "Cannot show cursor");

        (tcsetattr(stdoutFD, TCSANOW, &originalState) == 0).errnoEnforce(
                "Cannot set original termios state");
        import core.sys.posix.unistd : close;

        selfSignalFDs[0].close();
        selfSignalFDs[1].close();

        terminalThreadFDs[0].close();
        terminalThreadFDs[1].close();
    }

    auto putString(string s)
    {
        w(s);
        return this;
    }

    auto xy(int x, int y)
    {
        w(Operation.CURSOR_POSITION.execute((y + 1).to!string, (x + 1).to!string));
        return this;
    }

    final void wDirect(string data, lazy string errorMessage)
    {
        import core.sys.posix.unistd : write;

        (2.write(data.ptr, data.length) == data.length).errnoEnforce(errorMessage);
    }

    final void w(string data)
    {
        buffer.put(cast(char[]) data);
    }

    auto clearBuffer()
    {
        buffer.clear;
        w(Operation.CLEAR_TERMINAL.execute);
        return this;
    }

    auto flip()
    {
        auto data = buffer.data;
        // was 2 ???
        import core.sys.posix.unistd : write;

        (2.write(data.ptr, data.length) == data.length).errnoEnforce("Cannot blit data");
        return this;
    }

    Dimension dimension()
    {
        winsize ws;
        (ioctl(stdoutFD, TIOCGWINSZ, &ws) == 0).errnoEnforce("Cannot get winsize");
        return Dimension(ws.ws_col, ws.ws_row);
    }

    void runInTerminalThread(void delegate() d)
    {
        synchronized (this)
        {
            terminalThreadDelegates ~= d;
        }
        ubyte h = 0;
        import core.sys.posix.unistd : write;

        (terminalThreadFDs[1].write(&h, h.sizeof) == h.sizeof).errnoEnforce(
                "Cannot write ubyte to terminalThreadFD");
    }

    immutable(KeyInput) getInput()
    {
        import core.sys.posix.unistd : read;

        Tokenizer tokenizer = new Tokenizer();
        while (true)
        {
            // osx needs to do select when working with /dev/tty https://nathancraddock.com/blog/macos-dev-tty-polling/
            scope sel = new SelectSet();
            sel.addFD(selfSignalFDs[0]);
            sel.addFD(terminalThreadFDs[0]);
            sel.addFD(stdinFD);

            int result = sel.readyForRead();
            if (result == -1)
                return KeyInput.fromInterrupt();

            if (sel.isSet(selfSignalFDs[0]))
            {
                int buf;
                auto count = selfSignalFDs[0].read(&buf, buf.sizeof);
                (count == buf.sizeof).errnoEnforce("Cannot read on self signal fds read end");
                return KeyInput.fromCtrlC();
            }

            if (sel.isSet(terminalThreadFDs[0]))
            {
                ubyte buf;
                auto count = read(terminalThreadFDs[0], &buf, buf.sizeof);
                (count == buf.sizeof).errnoEnforce(format("Cannot read next delegate on fd %s",
                        terminalThreadFDs[0]));
                if (terminalThreadDelegates.length > 0)
                {
                    void delegate() h;
                    synchronized (this)
                    {
                        h = terminalThreadDelegates[0];
                        terminalThreadDelegates = terminalThreadDelegates[1 .. $];
                    }
                    h();
                }
                // delegate ran — loop back to check for input
                continue;
            }

            if (sel.isSet(stdinFD))
            {
                byte b;
                auto count = stdinFD.read(&b, 1);
                (count != -1).errnoEnforce("Cannot read next input byte");
                if (count == 0)
                {
                    continue;
                }
                auto keyInput = tokenizer.feed(b);
                if (keyInput)
                {
                    return keyInput;
                }
            }
        }
    }
}

alias InputHandler = bool delegate(KeyInput input);
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

    int left; /// Left position of the component relative to the parent
    int top; /// Top position of the component relative to the parent
    int width; /// Width of the component
    int height; /// Height of the component

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

    void setInputHandler(InputHandler inputHandler)
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

    void setParent(Component parent)
    {
        this.parent = parent;
    }

    abstract void render(Context context);
    bool handlesInput()
    {
        return true;
    }

    bool focusable()
    {
        return false;
    }

    bool handleInput(KeyInput input)
    {
        if (input.key == Key.tab && input.eventType == EventType.press)
        {
            focusNext();
            return true;
        }
        if (focusPath !is null && focusPath.handleInput(input))
        {
            // does the parent (e.g. scroller) handle the input
            return true;
        }
        if (inputHandler !is null && inputHandler(input))
        {
            // does the installed input handler want to handle the key input
            return true;
        }
        return false;
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
            if (components.empty)
            {
                return;
            }
            if (currentFocusedComponent is null)
            {
                components.front.requestFocus;
            }
            else
            {
                components.cycle.find(currentFocusedComponent).next.requestFocus;
            }
        }
        else
        {
            parent.focusNext();
        }
    }

    private Component[] findAllFocusableComponents(Component[] result = null)
    {
        if (focusable())
        {
            result ~= this;
        }
        foreach (child; children)
        {
            result = child.findAllFocusableComponents(result);
        }
        return result;
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

int clipTo(int v, size_t maximum)
{
    return min(v, maximum);
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

struct Viewport
{
    int x;
    int y;
    int width;
    int height;
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
        return "Context(left=%s, top=%s, width=%s, height=%s, viewport=%s)".format(left,
                top, width, height, viewport);
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

    /// low level output (taking left/top, viewport and scroll into account)
    auto putString(int x, int y, string s)
    {
        int scrolledY = y - viewport.y;
        if (scrolledY < 0)
        {
            return this;
        }
        if (scrolledY >= viewport.height)
        {
            return this;
        }
        // dfmt off
        terminal
            .xy(left + x, top + scrolledY)
            .putString(
                s.dropIgnoreAnsiEscapes(viewport.x)
                .takeIgnoreAnsiEscapes(viewport.width));
        // dfmt on
        return this;
    }

    // see https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm#All_cases
    void line(const(Position) from, const(Position) to, const(string) what)
    {
        const int dx = (to.x - from.x).abs;
        const int stepX = from.x < to.x ? 1 : -1;

        const int dy = -(to.y - from.y).abs;
        const int stepY = from.y < to.y ? 1 : -1;

        int error = dx + dy;
        int x = from.x;
        int y = from.y;
        while (true)
        {
            putString(x, y, what);
            if (x == to.x && y == to.y)
            {
                break;
            }
            const e2 = 2 * error;
            if (e2 >= dy)
            {
                if (x == to.x)
                {
                    break;
                }
                error += dy;
                x += stepX;
            }
            if (e2 <= dx)
            {
                if (y == to.y)
                {
                    break;
                }
                error += dx;
                y += stepY;
            }
        }
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
        signal(SIGWINCH, &windowSizeChangedSignalHandler);
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
            terminal.clearBuffer();
            foreach (root; roots)
            {
                scope context = new Context(terminal, root.left, root.top,
                        root.width, root.height);
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
        auto dimension = terminal.dimension;
        foreach (root; roots)
        {
            root.resize(0, 0, dimension.width, dimension.height);
        }
    }

    bool handleInput(KeyInput input)
    {
        return roots[$ - 1].handleInput(input);
    }
}

struct Refresh
{
}
