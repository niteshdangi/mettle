// profiles: debug release
import core.num
import std.panic.{catch_panic, CatchResult}

fn panics(body: fn(): Unit): bool {
    match take catch_panic(body) {
        CatchResult.Panicked(_) => true,
        CatchResult.Returned(_) => false
    }
}

fn main(): i32 {
    if !panics(fn(): Unit {
        let _ = capture num.from_str_radix<i128>("1", 37u32)
    }) { return 1 }
    if !panics(fn(): Unit {
        let _ = capture num.from_str_radix<i128>("1", 1u32)
    }) { return 2 }
    if !panics(fn(): Unit {
        let _ = capture num.from_str_radix<u64>("1", 37u32)
    }) { return 3 }
    if !panics(fn(): Unit {
        let _ = capture num.from_str_radix<u64>("1", 1u32)
    }) { return 4 }
    if !panics(fn(): Unit {
        let _ = capture num.from_str_radix<u8>("1", 37u32)
    }) { return 5 }
    if !panics(fn(): Unit {
        let _ = capture num.from_str_radix<u8>("1", 1u32)
    }) { return 6 }
    0
}
