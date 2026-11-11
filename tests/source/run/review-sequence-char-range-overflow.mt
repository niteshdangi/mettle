// profiles: debug release
import core.iter.{Iterator, range_from}
import std.panic.CatchResult
fn main(): i32 {
    let result = std.panic.catch_panic(fn(): Unit {
        var source = range_from('\u{10ffff}')
        let _ = source.next()
        let _ = source.next()
    })
    match take result {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => panic("char range silently ended")
    }
    0
}
