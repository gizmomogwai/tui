import tui : Ui, Text, KeyInput, List, VSplit, ScrollPane, HSplit, Terminal, Button, MultilineText;
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
    auto top = new HSplit(5, new MultilineText("1 11111111111111111111\n2 22222222222222222222\n3 33333333333333333333\n4 44444444444444444444\n5 55555555555555555555"), columns);
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
