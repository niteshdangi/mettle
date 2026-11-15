// expect-exit: 0
// expect-stderr: "panicked: pair={1,2}\n"

import std.panic.{catch_panic, CatchResult}

static mut TRACE: i32 = 0

fn argument(value: i32): i32 {
    unsafe { TRACE = TRACE * 10 + value }
    value
}

fn main(): i32 {
    let result = catch_panic(fn(): i32 {
        core.debug_assert_matches!(0i32, 1,
            "pair={{{},{}}}", argument(1), argument(2))
        0
    })
    match take result {
        CatchResult.Panicked(info) => {
            if info.code() != 101 || info.message() != "pair={1,2}" { return 1 }
        },
        CatchResult.Returned(_) => { return 2 }
    }
    if unsafe { TRACE } != 12 { return 3 }
    0
}
