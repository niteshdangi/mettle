import core.fmt
import std.io.{Error, Writer}

type FailingWriter { calls: usize }
extend FailingWriter implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error {
        self.calls += 1usize
        throw std.io.from_raw_os_error(if self.calls == 1usize { 32 } else { 5 })
    }
    mut fn flush(): Unit throws Error {}
}

type RecoveringDisplay { retry: bool }
extend RecoveringDisplay implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let _ = capture f.write_str("a")
        if self.retry { try f.write_str("b") }
    }
}

fn main(): i32 {
    var writer = FailingWriter(0usize)
    let value = RecoveringDisplay(true)
    match take capture writer.write(f"{value}") {
        failure(error) => { if error.raw_os_error() != present(32) { return 1 } },
        success(_) => { return 2 }
    }
    if writer.calls != 1usize { return 3 }
    var ignored = FailingWriter(0usize)
    let value = RecoveringDisplay(false)
    match take capture ignored.write(f"{value}") {
        failure(error) => { if error.raw_os_error() != present(32) { return 4 } },
        success(_) => { return 5 }
    }
    0
}
