// expect-exit: 0
// expect-stderr: "panicked: first=1 second=2\npanicked: pair={3,4}\npanicked: boom\n"

import std.panic.{catch_panic, CatchResult}

static mut TRACE: i32 = 0

fn argument(value: i32): i32 {
    unsafe { TRACE = TRACE * 10 + value }
    value
}

fn message(take result: CatchResult<i32>, read expected: Text): bool {
    match take result {
        CatchResult.Panicked(info) => info.code() == 101 && info.message() == expected,
        CatchResult.Returned(_) => false
    }
}

fn main(): i32 {
    let recipe = catch_panic(fn(): i32 {
        core.assert_matches!(0i32, 1,
            f"first={argument(1)} second={argument(2)}")
        0
    })
    if !message(recipe, "first=1 second=2") { return 1 }
    if unsafe { TRACE } != 12 { return 2 }
    let template = catch_panic(fn(): i32 {
        core.assert_matches!(0i32, 0 if false,
            "pair={{{},{}}}", argument(3), argument(4))
        0
    })
    if !message(template, "pair={3,4}") { return 3 }
    if unsafe { TRACE } != 1234 { return 4 }
    let text = catch_panic(fn(): i32 { core.panic.panic("boom") })
    if !message(text, "boom") { return 5 }
    0
}
