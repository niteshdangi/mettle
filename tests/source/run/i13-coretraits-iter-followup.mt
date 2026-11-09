import core.iter
import core.iter.Iterator

fn accumulate(mut state: i32, take item: i32): i32? {
    state += item
    present(state)
}

fn checked_add(take total: i32, take item: i32): i32 throws i32 {
    if item == 3 { throw 9 }
    total + item
}

fn checked_item(take item: i32): Unit throws i32 {
    if item == 2 { throw 7 }
}

fn main(): i32 {
    var remaining = iter.range(1, 5)
    {
        var borrowed = remaining.by_ref().take_n(2usize)
        match take borrowed.next() {
            present(value) => { if value != 1 { return 1 } },
            none => { return 1 }
        }
        match take borrowed.next() {
            present(value) => { if value != 2 { return 1 } },
            none => { return 1 }
        }
    }
    match take remaining.next() {
        present(value) => { if value != 3 { return 2 } },
        none => { return 2 }
    }
    if remaining.count() != 1usize { return 2 }

    let values = [1i32, 2i32, 3i32]
    if values.iter().copied().fold(0, fn(take sum: i32, take value: i32): i32 {
        sum + value
    }) != 6 {
        return 3
    }
    if values.iter().cloned().fold(0, fn(take sum: i32, take value: i32): i32 {
        sum + value
    }) != 6 {
        return 4
    }

    var scanned = iter.range(1, 4).scan(0i32, accumulate)
    if scanned.fold(0, fn(take sum: i32, take value: i32): i32 {
        sum + value
    }) != 10 {
        return 5
    }

    var folded = iter.range(1, 5)
    match take folded.try_fold(0i32, checked_add) {
        success(_) => { return 6 },
        failure(error) => { if error != 9 { return 7 } }
    }
    match take folded.next() {
        present(value) => { if value != 4 { return 8 } },
        none => { return 8 }
    }

    var visited = iter.range(1, 5)
    match take visited.try_for_each(checked_item) {
        success(_) => { return 9 },
        failure(error) => { if error != 7 { return 10 } }
    }
    match take visited.next() {
        present(value) => { if value != 3 { return 11 } },
        none => { return 11 }
    }
    0
}
