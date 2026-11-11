// profiles: debug release
import core.iter.{Iterator, BidirectionalIterator}
import std.panic.CatchResult

type Replacement { yielded: bool }
extend Replacement implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.yielded { panic("replacement stop") }
        self.yielded = true
        present(6)
    }
}

fn main(): i32 {
    var values = alloc.vec.new<i32>()
    values.push(10)
    values.push(20)
    values.push(30)
    var visits = 0usize
    {
        var extracted = values.extract_if(0usize..3usize, fn(mut value: i32): bool {
            visits += 1usize
            if value == 20 { value = 21; panic("extract stop") }
            true
        })
        if extracted.next().unwrap() != 10 { return 1 }
        let result = std.panic.catch_panic(fn(): Unit { let item = extracted.next() })
        match take result {
            CatchResult.Panicked(info) => { if info.message() != "extract stop" { return 2 } },
            CatchResult.Returned(_) => { return 3 }
        }
        if extracted.next().is_present() || extracted.next().is_present() { return 4 }
    }
    if visits != 2usize { return 5 }
    if values.len() != 2usize || values[0usize] != 21 || values[1usize] != 30 { return 6 }
    values.push(40)
    values.push(50)
    {
        var extracted = values.extract_if(1usize..3usize, fn(mut value: i32): bool { value == 30 })
        if extracted.next().unwrap() != 30 { return 7 }
    }
    if values != [21, 40, 50] { return 8 }
    var replacement = alloc.vec.new<i32>()
    replacement.push(7)
    replacement.push(8)
    replacement.push(9)
    {
        var removed = values.splice(1usize..2usize, take replacement)
        if removed.next_back().unwrap() != 40 { return 9 }
        if removed.next().is_present() { return 10 }
    }
    if values != [21, 7, 8, 9, 50] { return 11 }
    let interrupted = std.panic.catch_panic(fn(): Unit {
        let removed = values.splice(1usize..4usize, Replacement(false))
    })
    match take interrupted {
        CatchResult.Panicked(info) => { if info.message() != "replacement stop" { return 12 } },
        CatchResult.Returned(_) => { return 13 }
    }
    if values.len() < 2usize || *values.first().unwrap() != 21 || *values.last().unwrap() != 50 { return 14 }
    0
}
