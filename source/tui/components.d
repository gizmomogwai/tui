module tui.components;

import colored : forceStyle, Style;
import std.algorithm : max, min;
import std.exception : enforce;
import std.format : format;
import std.math.algebraic : abs;
import std.range : array, empty, front, split;
import std.signals;
import tui : clipTo, Component, Context, EventType, Key, KeyInput, Position, Viewport;

alias ButtonHandler = void delegate();

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

class Border : Component
{
    Component child;
    string title;
    this(string title, Component child)
    {
        this.title = title;
        this.child = child;
    }

    override void render(Context context)
    {
        enum TL = "╭";
        enum BR = "╯";
        enum TR = "╮";
        enum BL = "╰";
        enum H = "─";
        enum V = "│";
        context.line(Position(0, 0), Position(width, 0), H);
        context.line(Position(0, height - 1), Position(width, height - 1), H);
        context.line(Position(0, 0), Position(0, height - 1), V);
        context.line(Position(width - 1, 0), Position(width - 1, height - 1), V);
        context.putString(0, 0, TL);
        context.putString(width - 1, 0, TR);
        context.putString(0, height - 1, BL);
        context.putString(width - 1, height - 1, BR);
        context.putString(3, 0, " " ~ title ~ " ");
        child.render(context.forChild(child));
    }

    override void resize(int left, int top, int width, int height)
    {
        super.resize(left, top, width, height);
        this.child.resize(1, 1, width - 2, height - 2);
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

class MultilineText : Component
{
    string[] lines;
    this(string content)
    {
        lines = content.split("\n");
    }

    override void render(Context context)
    {
        foreach (idx, line; lines)
        {
            context.putString(0, cast(int) idx, line);
        }
    }

    override bool handlesInput()
    {
        return false;
    }
}

class Canvas : Component
{
    class Graphics
    {
        import std.uni : unicode;

        static braille = unicode.Braille.byCodepoint.array;
        int[] pixels;
        this()
        {
            pixels = new int[width * height];
        }

        int getWidth()
        {
            return width * 2;
        }

        int getHeight()
        {
            return height * 4;
        }
        // see https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm#All_cases
        void line(const(Position) from, const(Position) to)
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
                set(Position(x, y));
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
        // x and y in braille coords
        void set(const(Position) p)
        {
            enforce(p.x < getWidth(), "x: %s needs to be smaller than %s".format(p.x, getWidth));
            enforce(p.y < getHeight(), "y: %s needs to be smaller than %s".format(p.y, getHeight));
            enforce(p.x >= 0, "x: %s needs to be >= 0".format(p.x));
            enforce(p.y >= 0, "y: %s needs to be >= 0".format(p.y));
            // bit nr
            // 0 3
            // 1 4
            // 2 5
            // 6 7
            int xIdx = p.x / 2;
            int yIdx = p.y / 4;

            int brailleX = p.x % 2;
            int brailleY = p.y % 4;
            static brailleBits = [0, 1, 2, 6, 3, 4, 5, 7];
            int idx = xIdx + yIdx * width;
            pixels[idx] |= 1 << brailleBits[brailleY + brailleX * 4];
        }

        void render(Context context)
        {
            for (int j = 0; j < height; ++j)
            {
                for (int i = 0; i < width; ++i)
                {
                    const idx = i + j * width;
                    const p = pixels[idx];
                    if (p != 0)
                    {
                        context.putString(i, j, "%s".format(braille[p]));
                    }
                }
            }
        }
    }

    alias Painter = void delegate(Canvas.Graphics, Context);
    Painter painter;
    this(Painter painter)
    {
        this.painter = painter;
    }

    override void render(Context context)
    {
        scope g = new Graphics();
        painter(g, context);
        g.render(context);
    }

    override bool handlesInput()
    {
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
        if (input.eventType == EventType.press && input.key == Key.normal && input.c == ' ')
        {
            pressed();
            return true;
        }
        return false;
    }

    override bool focusable()
    {
        return true;
    }

    override string toString()
    {
        return "Button";
    }
}

class List(T, alias stringTransform) : Component
{
    T[] model;
    T[]delegate() getData;

    ScrollInfo scrollInfo;
    mixin Signal!(T) selectionChanged;
    bool vMirror;

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

    this(T[] model, bool vMirror = false)
    {
        this.model = model;
        this.scrollInfo = ScrollInfo(0, 0);
        this.vMirror = vMirror;
    }

    this(T[]delegate() getData, bool vMirror = false)
    {
        this.getData = getData;
        this.scrollInfo = ScrollInfo(0, 0);
        this.vMirror = vMirror;
    }

    override void render(Context context)
    {
        if (getData)
        {
            model = getData();
        }
        scrollInfo.offset = scrollInfo.offset.clipTo(model.length + -1);
        if (model.length + -1 < context.height)
        {
            scrollInfo.offset = 0;
        }
        scrollInfo.selection = scrollInfo.selection.clipTo(model.length + -1);
        for (int i = 0; i < height; ++i)
        {
            const index = i + scrollInfo.offset;
            if (index >= model.length)
                return;
            const selected = (index == scrollInfo.selection) && (currentFocusedComponent == this);
            static if (__traits(compiles, stringTransform(T.init, cast(size_t) 0)))
                auto text = "%s %s".format(selected ? ">" : " ",
                        stringTransform(model[index], width - 2));
            else
                auto text = "%s %s".format(selected ? ">" : " ", stringTransform(model[index]));
            text = selected ? text.forceStyle(Style.reverse) : text;
            context.putString(0, vMirror ? height - 1 - i : i, text);
        }
    }

    void up()
    {
        vMirror ? _down : _up;
    }

    void down()
    {
        vMirror ? _up : _down;
    }

    void _up()
    {
        if (model.empty)
        {
            return;
        }
        scrollInfo.up;
        selectionChanged.emit(model[scrollInfo.selection]);
    }

    void _down()
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
        if ((input.eventType == EventType.press) || (input.eventType == EventType.repeat))
        {
            switch (input.key)
            {
            case Key.up:
                up();
                return true;
            case Key.down:
                down();
                return true;
            default:
                return super.handleInput(input);
            }
        }
        return super.handleInput(input);
    }

    override bool focusable()
    {
        return true;
    }

    override string toString()
    {
        return "List";
    }
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
        viewport.y = max(viewport.y - 1, 0);
        return true;
    }

    bool down()
    {
        viewport.y++;
        return true;
    }

    bool left()
    {
        viewport.x = max(viewport.x - 1, 0);
        return true;
    }

    bool right()
    {
        viewport.x++;
        return true;
    }

    override bool handleInput(KeyInput input)
    {
        if ((input.eventType == EventType.press) || (input.eventType == EventType.repeat))
        {
            switch (input.key)
            {
            case Key.up:
                return up();
            case Key.down:
                return down();
            case Key.left:
                return left();
            case Key.right:
                return right();
            case Key.normal:
                {
                    switch (input.c)
                    {
                    case 'w', 'j':
                        return up();
                    case 's', 'k':
                        return down();
                    case 'a', 'h':
                        return left();
                    case 'd', 'l':
                        return right();
                    default:
                        break;
                    }
                    break;
                }
            default:
                break;
            }
        }
        return super.handleInput(input);
    }

    override bool focusable()
    {
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
