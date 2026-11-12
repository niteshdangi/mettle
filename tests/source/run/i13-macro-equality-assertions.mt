// profiles: debug release

import alloc.string.String
import std.macros.{assert_eq, assert_ne}
import std.panic.{catch_panic, CatchResult}

fn next(read count: core.cell.Cell<i32>): i32 {
    count.set(count.get() + 1)
    count.get()
}

fn main(): i32 {
    let left = String("kept")
    assert_eq!(left, String("kept"),)
    assert_ne!(left, String("different"))
    if left.as_text() != "kept" { return 1 }

    var left_calls = 0i32
    var right_calls = 0i32
    assert_eq!({ left_calls += 1; 7 }, { right_calls += 1; 7 })
    assert_ne!({ left_calls += 1; 8 }, { right_calls += 1; 9 },)
    if left_calls != 2 || right_calls != 2 { return 2 }

    let message_calls = core.cell.Cell.new(0i32)
    assert_eq!(1, 1, f"unused {next(read message_calls)}")
    if message_calls.get() != 0 { return 3 }

    let equal_failure = catch_panic(fn(): i32 {
        assert_eq!(2, 3)
        0
    })
    match take equal_failure {
        CatchResult.Panicked(info) => {
            if info.message() != "assertion failed: left == right\n  left: 2\n right: 3" {
                return 4
            }
        },
        CatchResult.Returned(_) => { return 5 }
    }

    let not_equal_failure = catch_panic(fn(): i32 {
        assert_ne!(5, 5, f"detail {next(read message_calls)}")
        0
    })
    match take not_equal_failure {
        CatchResult.Panicked(info) => {
            if info.message() != "assertion failed: left != right: detail 1\n  left: 5\n right: 5" {
                return 6
            }
        },
        CatchResult.Returned(_) => { return 7 }
    }
    if message_calls.get() != 1 { return 8 }
    0
}
