// profiles: debug release
// expect-stderr: "restored\n"

import std.macros.eprintln
import std.panic.{catch_panic, CatchResult}
import std.sys

extern "C" {
    unsafe fn dup2(source: i32, target: i32): i32;
}

fn main(): i32 {
    let saved = unsafe { sys.mettle_rt_dup(2i32) }
    if saved < 0i32 { return 2 }
    if unsafe { sys.close(2i32) } != 0i32 { return 3 }
    let message_result = catch_panic(fn(): i32 {
        eprintln("must fail")
        0
    })
    let newline_result = catch_panic(fn(): i32 {
        eprintln("")
        0
    })
    if unsafe { dup2(saved, 2i32) } != 2i32 { return 4 }
    if unsafe { sys.close(saved) } != 0i32 { return 5 }

    match take message_result {
        CatchResult.Panicked(info) => {
            if info.code() != 101 || info.message() != "failed to write to standard error" { return 6 }
        },
        CatchResult.Returned(_) => { return 7 }
    }
    match take newline_result {
        CatchResult.Panicked(info) => {
            if info.code() != 101 || info.message() != "failed to write to standard error" { return 8 }
        },
        CatchResult.Returned(_) => { return 9 }
    }
    eprintln("restored")
    0
}
