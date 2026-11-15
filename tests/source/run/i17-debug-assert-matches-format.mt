// profiles: debug
import std.panic.{catch_panic, CatchResult}

fn next(read calls: core.cell.Cell<i32>): i32 {
    calls.set(calls.get() + 1)
    calls.get()
}

fn main(): i32 {
    let expected = 1i32
    let actual = 2i32
    let core_failure = catch_panic(fn(): Unit {
        core.debug_assert_matches!(actual, 1i32, f"expected {expected}, found {actual}")
    })
    match take core_failure {
        CatchResult.Panicked(info) => {
            if info.message() != "expected 1, found 2" { return 1 }
        },
        CatchResult.Returned(_) => { return 1 }
    }

    let std_failure = catch_panic(fn(): Unit {
        std.debug_assert_matches!(actual, 1i32, f"expected {expected}, found {actual}")
    })
    match take std_failure {
        CatchResult.Panicked(info) => {
            if info.message() != "expected 1, found 2" { return 2 }
        },
        CatchResult.Returned(_) => { return 2 }
    }

    let variadic_failure = catch_panic(fn(): Unit {
        core.debug_assert_matches!(actual, 1i32, "expected {}, found {}", expected, actual)
    })
    match take variadic_failure {
        CatchResult.Panicked(info) => {
            if info.message() != "expected 1, found 2" { return 3 }
        },
        CatchResult.Returned(_) => { return 3 }
    }

    let escaped_failure = catch_panic(fn(): Unit {
        std.debug_assert_matches!(actual, 1i32, "{{expected}} {}, {}", expected, actual)
    })
    match take escaped_failure {
        CatchResult.Panicked(info) => {
            if info.message() != "{expected} 1, 2" { return 4 }
        },
        CatchResult.Returned(_) => { return 4 }
    }

    let calls = core.cell.Cell.new(0i32)
    let ordered_failure = catch_panic(fn(): Unit {
        core.debug_assert_matches!(actual, 1i32, "{} then {}", next(read calls), next(read calls))
    })
    match take ordered_failure {
        CatchResult.Panicked(info) => {
            if info.message() != "1 then 2" { return 5 }
        },
        CatchResult.Returned(_) => { return 5 }
    }
    if calls.get() != 2 { return 6 }
    0
}
