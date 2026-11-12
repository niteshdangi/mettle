// profiles: debug release
// expect-stdout: "plain count=3\nforwarded=5\n"
// expect-stderr: "diagnostic=4\n"
// Mettle's native macro equivalents and the prelude assert/panic behavior.

import core.panic.unreachable
import core.fmt
import alloc.string.String
import std.io
import std.macros.{dbg, format_args, matches, todo, unimplemented}
import std.panic.{catch_panic, CatchResult}

fn panic_message(take outcome: CatchResult<i32>, read expected: Text): i32 {
    match take outcome {
        CatchResult.Panicked(info) => {
            if info.code() != 101 { return 1 }
            if info.message() != expected { return 2 }
            0
        },
        CatchResult.Returned(_) => { 3 }
    }
}

fn main(): i32 {
    assert(1 < 2, "arithmetic holds")
    assert(3 == 3, "equal values match")
    assert(3 != 4, "different values differ")
    var dbg_calls = 0i32
    let dbg_value = dbg!({ dbg_calls += 1; 42i32 })
    if dbg_calls != 1 || dbg_value != 42 { return 43 }
    let dbg_pair = dbg!({ dbg_calls += 1; dbg_calls }, { dbg_calls *= 2; dbg_calls },)
    if dbg_calls != 4 || dbg_pair.0 != 2 || dbg_pair.1 != 4 { return 44 }
    let absent: i32? = none
    if !matches!(present(3i32), present(_)) || matches!(absent, present(_)) { return 42 }
    var match_calls = 0i32
    var guard_calls = 0i32
    if !matches!({ match_calls += 1; present(3i32) }, present(value) if {
        guard_calls += 1
        value == 3
    },) { return 45 }
    if matches!(absent, present(_) if { guard_calls += 1; true }) { return 46 }
    if matches!(present(3i32), present(value) if value == 4) { return 47 }
    if match_calls != 1 || guard_calls != 1 { return 48 }
    var formatted = String("")
    match take capture formatted.write_fmt(format_args!(f"count={3}\n")) {
        success(_) => {},
        failure(_) => { return 40 }
    }
    if formatted.as_text() != "count=3\n" { return 41 }
    io.print("plain ")
    io.print(f"count={3}\n")
    io.eprint(f"diagnostic={4}\n")
    io.print(format_args!(f"forwarded={5}\n"))

    let failed_assert = catch_panic(fn(): i32 {
        assert(false, "boom")
        0
    })
    let assert_code = panic_message(failed_assert, "boom")
    if assert_code != 0 { return 10 + assert_code }

    let explicit = catch_panic(fn(): i32 { panic("boom") })
    let explicit_code = panic_message(explicit, "boom")
    if explicit_code != 0 { return 20 + explicit_code }

    let unreached = catch_panic(fn(): i32 {
        unreachable()
    })
    let unreachable_code = panic_message(unreached, "entered unreachable code")
    if unreachable_code != 0 { return 30 + unreachable_code }

    let todo_default = catch_panic(fn(): i32 { todo!(); 0 })
    let todo_default_code = panic_message(todo_default, "not yet implemented")
    if todo_default_code != 0 { return 50 + todo_default_code }
    let todo_custom = catch_panic(fn(): i32 { todo!("later"); 0 })
    let todo_custom_code = panic_message(todo_custom, "later")
    if todo_custom_code != 0 { return 60 + todo_custom_code }

    let unimplemented_default = catch_panic(fn(): i32 { unimplemented!(); 0 })
    let unimplemented_default_code = panic_message(unimplemented_default, "not implemented")
    if unimplemented_default_code != 0 { return 70 + unimplemented_default_code }
    let unimplemented_custom = catch_panic(fn(): i32 { unimplemented!("missing"); 0 })
    let unimplemented_custom_code = panic_message(unimplemented_custom, "missing")
    if unimplemented_custom_code != 0 { return 80 + unimplemented_custom_code }
    0
}
