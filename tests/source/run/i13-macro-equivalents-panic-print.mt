// profiles: debug release
// Mettle's counterparts of the assert, panic, unreachable and print/format macros:
// the prelude `assert` and `panic`, `core.panic.unreachable`, and `std.io` print
// functions with format messages.

import core.panic.unreachable
import std.io
import std.panic.{catch_panic, CatchResult}

fn panic_message(outcome: take CatchResult<i32>, length: usize): i32 {
    match take outcome {
        CatchResult.Panicked(info) => {
            if info.code() != 101 { return 1 }
            if info.message().len() != length { return 2 }
            0
        },
        CatchResult.Returned(_) => { 3 }
    }
}

fn main(): i32 {
    assert(1 < 2, "arithmetic holds")
    io.print("plain ")
    io.print(f"count={3}\n")
    io.eprint(f"diagnostic={4}\n")

    let failed_assert = catch_panic(fn(): i32 {
        assert(false, "boom")
        0
    })
    let assert_code = panic_message(failed_assert, 4usize)
    if assert_code != 0 { return 10 + assert_code }

    let explicit = catch_panic(fn(): i32 { panic("boom") })
    let explicit_code = panic_message(explicit, 4usize)
    if explicit_code != 0 { return 20 + explicit_code }

    let unreached = catch_panic(fn(): i32 {
        unreachable()
    })
    let unreachable_code = panic_message(unreached, 24usize)
    if unreachable_code != 0 { return 30 + unreachable_code }
    0
}
