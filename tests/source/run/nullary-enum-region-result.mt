enum Choice<region r> { Empty, Value(read i32 from r) }

fn empty<region r>(source: read i32 from r): Choice<region r> {
    Choice.Empty
}

fn explicit<region r>(source: read i32 from r): Choice<region r> {
    Choice<region r>.Empty
}

fn optional<region r>(source: read i32 from r): Choice<region r>? {
    present(Choice.Empty)
}

fn main(): i32 {
    let value = 7
    match empty(value) {
        Choice.Empty => {},
        _ => { return 1 }
    }
    match explicit(value) {
        Choice.Empty => {},
        _ => { return 2 }
    }
    match optional(value) {
        present(Choice.Empty) => {},
        _ => { return 3 }
    }
    match Choice.Value(read value) {
        Choice.Value(payload) => { if *payload != 7 { return 4 } },
        _ => { return 5 }
    }
    0
}
