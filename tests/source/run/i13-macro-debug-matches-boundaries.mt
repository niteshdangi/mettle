// profiles: debug release
// expect-stderr: "\"owned\"\npretty\n"

import alloc.string.String
import core.fmt
import std.macros.{dbg, matches}
import std.panic.{catch_panic, CatchResult}

type BrokenDebug {}
extend BrokenDebug implements fmt.Debug {
    fn fmt(mut formatter: fmt.Formatter): Unit throws fmt.Error {
        throw fmt.Error()
    }
}

type DebugProbe { pub value: i32 }
extend DebugProbe implements fmt.Debug {
    fn fmt(mut formatter: fmt.Formatter): Unit throws fmt.Error {
        if formatter.alternate() {
            try formatter.write_str("pretty")
        } else {
            try formatter.write_str("plain")
        }
    }
}

fn main(): i32 {
    let owned = dbg!(String("owned"),)
    if owned.as_text() != "owned" { return 1 }
    let probe = dbg!(DebugProbe(17))
    if probe.value != 17 { return 7 }

    let skipped = core.cell.Cell.new(0i32)
    let failed = catch_panic(fn(): i32 {
        let _ = dbg!(BrokenDebug(), { skipped.set(skipped.get() + 1); 42i32 })
        0
    })
    match take failed {
        CatchResult.Panicked(info) => {
            if info.message() != "debug formatting failed" { return 2 }
        },
        CatchResult.Returned(_) => { return 3 }
    }
    if skipped.get() != 0 { return 4 }

    var evaluations = 0i32
    var guards = 0i32
    if !matches!({
        evaluations += 1
        present(String("value"))
    }, present(value) if {
        guards += 1
        value.as_text() == "value"
    },) { return 5 }
    if evaluations != 1 || guards != 1 { return 6 }
    0
}
