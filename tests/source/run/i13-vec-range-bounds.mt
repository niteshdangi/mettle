import alloc.vec
import core.iter.Bound

fn main(): i32 {
    var values = vec.new<i32>()
    var i = 0
    while i < 6 {
        let item: i32 = i
        values.push(item)
        i += 1
    }

    {
        var removed = values.drain(1usize..=3usize)
        if removed.size_hint() != (3usize, present(3usize)) { return 1 }
        match take removed.next() {
            present(value) => { if value != 1 { return 2 } },
            none => { return 3 }
        }
        match take removed.next_back() {
            present(value) => { if value != 3 { return 4 } },
            none => { return 5 }
        }
        match take removed.next() {
            present(value) => { if value != 2 { return 6 } },
            none => { return 7 }
        }
    }
    if values.len() != 3usize || values[0usize] != 0 ||
        values[1usize] != 4 || values[2usize] != 5 {
        return 8
    }

    {
        var removed = values.drain(core.iter.range_to(1usize))
        match take removed.next() {
            present(value) => { if value != 0 { return 9 } },
            none => { return 10 }
        }
    }
    {
        var removed = values.drain(core.iter.range_from(1usize))
        match take removed.next() {
            present(value) => { if value != 5 { return 11 } },
            none => { return 12 }
        }
    }
    if values.len() != 1usize || values[0usize] != 4 { return 13 }

    var tuple_range = vec.new<i32>()
    tuple_range.push(10)
    tuple_range.push(20)
    tuple_range.push(30)
    {
        var removed = tuple_range.drain(
            (Bound.Excluded(0usize), Bound.Included(2usize))
        )
        if removed.size_hint() != (2usize, present(2usize)) { return 14 }
        match take removed.next() {
            present(value) => { if value != 20 { return 15 } },
            none => { return 16 }
        }
        match take removed.next_back() {
            present(value) => { if value != 30 { return 17 } },
            none => { return 18 }
        }
    }
    if tuple_range.len() != 1usize || tuple_range[0usize] != 10 { return 19 }

    var extracted = vec.new<i32>()
    extracted.push(1)
    extracted.push(2)
    extracted.push(3)
    {
        var items = extracted.extract_if(core.iter.range_full(), fn(mut value: i32): bool {
            value == 2
        })
        match take items.next() {
            present(value) => { if value != 2 { return 20 } },
            none => { return 27 }
        }
        if items.next().is_present() { return 21 }
    }
    if extracted.len() != 2usize || extracted[0usize] != 1 ||
        extracted[1usize] != 3 {
        return 22
    }

    var spliced = vec.new<i32>()
    spliced.push(10)
    spliced.push(20)
    spliced.push(30)
    spliced.push(40)
    var replacement = vec.new<i32>()
    replacement.push(80)
    replacement.push(90)
    {
        var removed = spliced.splice(1usize..3usize, replacement)
        match take removed.next() {
            present(value) => { if value != 20 { return 23 } },
            none => { return 24 }
        }
    }
    if spliced.len() != 4usize || spliced[0usize] != 10 ||
        spliced[1usize] != 80 || spliced[2usize] != 90 ||
        spliced[3usize] != 40 {
        return 25
    }

    var copied = vec.new<i32>()
    copied.push(1)
    copied.push(2)
    copied.push(3)
    copied.extend_from_within(1usize..3usize)
    if copied.len() != 5usize || copied[3usize] != 2 ||
        copied[4usize] != 3 {
        return 26
    }
    0
}
