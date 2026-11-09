// expect-exit: 0
import alloc.vec
import std.panic.CatchResult

fn main(): i32 {
    var values = vec.new<i32>()
    values.push(10)
    values.push(20)
    values.push(30)

    let reversed = std.panic.catch_panic(fn(): i32 {
        let _drain = values.drain(2usize..1usize)
        0
    })
    match take reversed {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    if values.len() != 3usize || values[0usize] != 10 ||
        values[1usize] != 20 || values[2usize] != 30 {
        return 2
    }

    let out_of_bounds = std.panic.catch_panic(fn(): i32 {
        let _items = values.extract_if(1usize..4usize,
            fn(mut value: i32): bool { value == 20 })
        0
    })
    match take out_of_bounds {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 3 }
    }
    if values.len() != 3usize || values[1usize] != 20 { return 4 }

    let overflow = std.panic.catch_panic(fn(): i32 {
        let _drain = values.drain(core.iter.range_to_inclusive(0xffffffffffffffffusize))
        0
    })
    match take overflow {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 5 }
    }
    if values.len() != 3usize || values[0usize] != 10 ||
        values[1usize] != 20 || values[2usize] != 30 {
        return 6
    }

    let invalid_splice = std.panic.catch_panic(fn(): i32 {
        var replacement = vec.new<i32>()
        replacement.push(99)
        let _items = values.splice(1usize..4usize, replacement)
        0
    })
    match take invalid_splice {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 7 }
    }
    if values.len() != 3usize || values[0usize] != 10 ||
        values[1usize] != 20 || values[2usize] != 30 {
        return 8
    }
    0
}
