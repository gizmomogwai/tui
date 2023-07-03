import tui : Ui, Text, KeyInput, List, VSplit, ScrollPane, HSplit, Terminal, Button, MultilineText, Canvas, Context, Position;
import std;

class Text2 : Text
{
    this(string text)
    {
        super(text);
    }

    void dataChanged(int i)
    {
        import std.file : append;
        this.content = "Selection changed to %s".format(i);
    }
}

struct State
{
    bool finished;
}

string longText() {
    return iota(1, 100)
        .map!(i => i.to!string.leftJustify(200, 'x')~i.to!string)
        .joiner("\n")
        .to!string;
}

int main(string[] args)
{
    KeyInput keyInput;
    scope terminal = new Terminal;
    auto ui = new Ui(terminal);
    State state = {finished: false,};
    auto canvas = new Canvas((Canvas.Graphics graphics, Context context) {
            static int dx = 1;
            static int x = 0;
            graphics.line(Position(0, 0), Position(x, graphics.getHeight-1));
            x += dx;
            if (x >= graphics.getWidth())
            {
                dx = -1;
                x += dx;
            }
            if (x < 0)
            {
                dx = 1;
                x += dx;
            }

            static int y = 0;
            static int dy = 1;
            graphics.set(Position(graphics.getWidth-1, y));
            y += dy;
            if (y >= graphics.getHeight())
            {
                dy = -1;
                y += dy;
            }
            if (y < 0)
            {
                dy = 1;
                y += dy;
            }
        });
    auto status = new Text2("The current state");
    auto list1 = new List!(int, i => i.to!string)(iota(1, 100).array);
    auto list2 = new List!(int, i => i.to!string)(iota(100, 200).array);
    list1.selectionChanged.connect(&status.dataChanged);
    list1.setInputHandler((input) {
        switch (input.input)
        {
        case "1":
            auto _pop = { ui.pop(); };
            auto b1 = new Button("finish1", _pop);
            auto b2 = new Button("finish2", _pop);
            auto popup = new VSplit(50, b1, b2);
            ui.push(popup);
            return true;
        default:
            return false;
        }
    });
    list2.selectionChanged.connect(&status.dataChanged);
    list1.select;
    auto leftSide = new VSplit(20, list1, list2);
    auto rightSide = new ScrollPane(new MultilineText(longText));
    auto columns = new VSplit(60, leftSide, rightSide);
    auto top = new HSplit(5, canvas/+new MultilineText("1 11111111111111111111\n2 22222222222222222222\n3 33333333333333333333\n4 44444444444444444444\n5 55555555555555555555")+/, columns);
    auto root = new HSplit(-5, top, status);

    ui.push(root);
    ui.resize;
    while (!state.finished)
    {
        ui.render;
        auto input = terminal.getInput();
        ui.handleInput(cast()input);
    }
    return 0;
}
