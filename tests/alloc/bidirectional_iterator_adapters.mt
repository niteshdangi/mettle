import alloc.vec
import alloc.vec.List
import core.iter.{Iterator, BidirectionalIterator}

fn four_values(): List<i32> {
    var values = vec.new<i32>()
    values.push(1)
    values.push(2)
    values.push(3)
    values.push(4)
    values
}

fn main(): i32 {
    var mapped = four_values().into_iter().map(fn(value: take i32): i32 { value * 10 })
    match mapped.next_back() {
        present(value) => { if value != 40 { return 1 } },
        none => { return 2 }
    }
    match mapped.next() {
        present(value) => { if value != 10 { return 3 } },
        none => { return 4 }
    }

    var filtered = four_values().into_iter().filter(fn(value: read i32): bool {
        value % 2 == 0
    })
    match filtered.next_back() {
        present(value) => { if value != 4 { return 5 } },
        none => { return 6 }
    }
    match filtered.next() {
        present(value) => { if value != 2 { return 7 } },
        none => { return 8 }
    }

    var reversed = four_values().into_iter().rev()
    match reversed.next() {
        present(value) => { if value != 4 { return 9 } },
        none => { return 10 }
    }
    match reversed.next_back() {
        present(value) => { if value != 1 { return 11 } },
        none => { return 12 }
    }

    var left = vec.new<i32>()
    left.push(1)
    left.push(2)
    var right = vec.new<i32>()
    right.push(3)
    right.push(4)
    var chained = left.into_iter().chain(right.into_iter())
    match chained.next_back() {
        present(value) => { if value != 4 { return 13 } },
        none => { return 14 }
    }
    match chained.next() {
        present(value) => { if value != 1 { return 15 } },
        none => { return 16 }
    }
    match chained.next_back() {
        present(value) => { if value != 3 { return 17 } },
        none => { return 18 }
    }

    var enumerated_values = vec.new<i32>()
    enumerated_values.push(7)
    enumerated_values.push(8)
    var enumerated = enumerated_values.into_iter().enumerate()
    match enumerated.next() {
        present(pair) => {
            if pair.0 != 0usize || pair.1 != 7 { return 19 }
        },
        none => { return 20 }
    }
    match enumerated.next() {
        present(pair) => {
            if pair.0 != 1usize || pair.1 != 8 { return 21 }
        },
        none => { return 22 }
    }
    0
}
