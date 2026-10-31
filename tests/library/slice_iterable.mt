import alloc.vec.List
import core.iter.{Iterator, Iterable, MutableIterable}

fn sum<C: Iterable<Item = i32> + unsized>(items: read C): i32 {
    var total = 0
    for item in items { total += *item }
    total
}

fn main(): i32 {
    var values = [1, 2, 3]
    {
        let slice: read [i32] = read values
        var total = 0
        for item in slice { total += item }
        if total != 6 { return 1 }

        var iter = slice.iter()
        match iter.next() {
            present(item) => { if *item != 1 { return 2 } },
            none => { return 2 }
        }
        var protocol_iter = [i32].(Iterable).iter(slice)
        match protocol_iter.next() {
            present(item) => { if *item != 1 { return 2 } },
            none => { return 2 }
        }
        if sum(slice) != 6 { return 4 }
    }

    {
        let slice: mut [i32] = mut values
        var iter = [i32].(MutableIterable).iter_mut(slice)
        match take iter.next() {
            present(item) => { if *item != 1 { return 2 } },
            none => { return 2 }
        }
    }
    {
        let slice: mut [i32] = mut values
        for item in slice { item += 1 }
    }
    if values[0] != 2 || values[1] != 3 || values[2] != 4 { return 3 }

    var list: List<i32> = alloc.vec.new<i32>()
    list.push(4)
    list.push(5)
    if sum(read list) != 9 { return 5 }
    0
}
