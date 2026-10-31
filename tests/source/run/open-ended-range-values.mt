import core.iter.Iterator

fn total<I: Iterator<Item = i32>>(items: take I): i32 {
    var source = items
    var sum = 0
    while true {
        match take source.next() {
            present(value) => { sum += value },
            none => { break }
        }
    }
    sum
}

fn main(): i32 {
    if total((4..).take_n(3usize)) != 15 { return 1 }
    let upper: core.iter.RangeTo<i32> = ..5
    let inclusive_upper: core.iter.RangeToInclusive<i32> = ..=5
    let full: core.iter.RangeFull = ..
    let _ = upper
    let _ = inclusive_upper
    let _ = full
    0
}
