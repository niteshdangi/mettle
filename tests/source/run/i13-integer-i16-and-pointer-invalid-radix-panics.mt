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
        let _ = capture num.parse_radix<i16>("1", 37u32)
    }) { return 1 }
    if !panics(fn(): Unit {
        let _ = capture num.parse_radix<i16>("1", 1u32)
    }) { return 2 }
    if !panics(fn(): Unit {
        let _ = capture num.parse_radix<isize>("1", 37u32)
    }) { return 3 }
    if !panics(fn(): Unit {
        let _ = capture num.parse_radix<isize>("1", 1u32)
    }) { return 4 }
    if !panics(fn(): Unit {
        let _ = capture num.parse_radix<usize>("1", 37u32)
    }) { return 5 }
    if !panics(fn(): Unit {
        let _ = capture num.parse_radix<usize>("1", 1u32)
    }) { return 6 }
    0
}
