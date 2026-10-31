// Thread handles and scopes render a fixed text form with no runtime state.
import std.thread
import core.fmt
import core.fmt.Debug
import alloc.string

fn debug<T: Debug>(value: read T): string.String throws fmt.Error {
    var output = string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        try T.(Debug).fmt(value, mut formatter)
    }
    output
}

fn check(): i32 throws fmt.Error {
    let handle = thread.spawn(take fn(): i32 { 7 })
    if (try debug(handle)).as_text() != "JoinHandle { .. }" { return 1 }
    let joined = capture handle.join()
    match take joined {
        success(value) => { if value != 7 { return 2 } },
        failure(_) => { return 3 }
    }
    let scoped = thread.scope(take fn(s: read thread.Scope): i32 {
        let scope_text = capture debug(s)
        match take scope_text {
            success(text) => { if text.as_text() != "Scope { .. }" { return 4 } },
            failure(_) => { return 5 }
        }
        let child = s.spawn(take fn(): i32 { 9 })
        let child_text = capture debug(child)
        match take child_text {
            success(text) => { if text.as_text() != "ScopedJoinHandle { .. }" { return 6 } },
            failure(_) => { return 7 }
        }
        0
    })
    scoped
}

fn main(): i32 {
    match capture check() { success(result) => result, failure(_) => 99 }
}
