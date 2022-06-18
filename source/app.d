import tui;
import std;

class Text2 : Text {
    this(string text) {
        super(text);
    }
    void dataChanged(int i) {
        import std.file : append; "key.log".append("datachanged\n");

        this.content = "Selection changed to %s".format(i);
    }
}

struct State
{
    bool finished;
}

class DemoUi : Ui!(State) {
    this(Terminal terminal) {
        super(terminal);
    }
    override State handleKey(KeyInput input, State state)
    {
        switch (input.input) {
        case "\x1B":
            state.finished = true;
            break;
        default:
            roots[$-1].handleInput(input);
            break;
        }
        return state;
    }
}

int main(string[] args) {
    KeyInput keyInput;
    scope terminal = new Terminal;
    auto ui = new DemoUi(terminal);
    State state = { finished: false, };

    auto status = new Text2("The current state");
    auto list1 = new List!(int, i => i.to!string)(iota(1, 100).array);
    auto list2 = new List!(int, i => i.to!string)(iota(100, 200).array);
    list1.selectionChanged.connect(&status.dataChanged);
    list1.setInputHandler((input) {
            switch (input.input) {
            case "1":
                auto _pop = { ui.pop();};
                auto b1 = new Button("finish1", _pop);
                auto b2 = new Button("finish2", _pop);
                auto popup = new VSplit(50, b1, b2);
                popup.addToFocusComponents(b1);
                popup.addToFocusComponents(b2);
                ui.push(popup);
                return true;
            default:
                return false;
            }
        });
    list2.selectionChanged.connect(&status.dataChanged);
    list1.select;
    auto lists = new VSplit(20, list1, list2);
    auto root = new HSplit(-1, lists, status);
    root.addToFocusComponents(list1);
    root.addToFocusComponents(list2);

    ui.push(root);
    ui.resize;
    while (!state.finished) {
        ui.render;
        auto input = terminal.getInput();
        state = ui.handleKey(input, state);
    }
    return 0;
}
