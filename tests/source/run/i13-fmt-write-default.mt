// expect-exit: 0
// profiles: debug release

import core.fmt
import core.fmt.{Display, Error, Formatter, Write}
import core.text.Text

type Tracked<region r> {
    drops: mut i32 from r
    drop { *self.drops += 1 }
}
extend<region r> Tracked<region r> implements Display {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("tracked") }
}

type Failing {
    calls: usize
    accepted: usize
}
extend Failing implements Write {
    mut fn write_str(read text: Text): Unit throws Error {
        self.calls += 1usize
        if self.calls == 2usize { throw Error() }
        self.accepted += text.len()
    }
}

fn forward<W: Write + unsized>(mut sink: W, message: format fmt.Message): Unit throws Error {
    try sink.write_fmt(message)
}

fn checks(): i32 throws Error {
    var bytes = [0u8; 32]
    var sink = fmt.buffer_writer(mut bytes)
    try forward(mut sink, f"a{17i32}")
    {
        let erased: mut any Write = mut sink
        try forward(erased, f":{23i32}")
    }
    let length = sink.len()
    match fmt.written_text(read bytes, length) {
        present(text) => { if text != "a17:23" { return 1 } },
        none => { return 1 }
    }

    var failing = Failing(0usize, 0usize)
    var drops = 0i32
    let result = capture forward(mut failing, f"prefix{Tracked(mut drops)}tail")
    match result {
        success(_) => { return 2 },
        failure(_) => {}
    }
    if failing.calls != 2usize || failing.accepted != 6usize { return 3 }
    if drops != 1 { return 4 }
    0
}

fn main(): i32 {
    match capture checks() {
        success(code) => code,
        failure(_) => 99
    }
}
