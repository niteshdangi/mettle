// expect-exit: 101
// expect-stderr: panicked: not done yet
// todo, unimplemented and unreachable are Never-returning panics with fixed messages.
import core.panic
import std.panic.CatchResult

fn main(): i32 {
    match take std.panic.catch_panic(fn(): i32 {
        panic.unimplemented("later")
        1
    }) {
        CatchResult.Panicked(info) => { if info.message() != "later" { return 1 } },
        CatchResult.Returned(_) => { return 2 }
    }
    match take std.panic.catch_panic(fn(): i32 {
        panic.unreachable()
        1
    }) {
        CatchResult.Panicked(info) => { if info.message() != "entered unreachable code" { return 3 } },
        CatchResult.Returned(_) => { return 4 }
    }
    panic.todo("not done yet")
    0
}
