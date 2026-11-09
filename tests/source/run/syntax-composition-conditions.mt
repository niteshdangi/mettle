fn record(mut trace: i32, digit: i32, value: i32?): i32? {
    trace = trace * 10 + digit
    value
}

const fn choose(value: i32): i32 {
    if let (found, true) = (value, value > 0), found > 0 { found + 1 } else { 0 }
}
const fn count(limit: i32): i32 {
    var value = 0
    while let (found, true) = (value, value < limit), found < limit { value += 1 }
    value
}
const fn fallback(): i32 {
    let item = 9
    if let item = 1, false { item } else { item }
}
const CHOSEN: i32 = choose(4)
const COUNTED: i32 = count(3)
const FALLBACK: i32 = fallback()

fn wide(flag: bool): u64 {
    let chosen = if flag, true { 1 } else { 2u64 }
    chosen
}
fn earlier_exit(flag: bool): i32 {
    if flag, { return 42; true } { 0 } else { 7 }
}

fn main(): i32 {
    if CHOSEN != 5 || COUNTED != 3 || FALLBACK != 9 { return 1 }
    var trace = 0
    let combined = if let present(first) = record(trace, 1, present(4)),
                      first == 4,
                      let present(second) = record(trace, 2, present(7)),
                      second == 7 {
        first + second
    } else { 0 }
    if combined != 11 || trace != 12 { return 2 }

    let first = 99
    trace = 0
    let early = if let present(first) = record(trace, 3, none),
                   let present(second) = record(trace, 4, present(1)) {
        first + second
    } else { first }
    if early != 99 || trace != 3 { return 3 }

    trace = 0
    let late = if let present(first) = record(trace, 5, present(8)),
                  let present(second) = record(trace, 6, none),
                  let present(third) = record(trace, 7, present(1)) {
        first + second + third
    } else { first }
    if late != 99 || trace != 56 { return 4 }

    trace = 0
    if false, let present(unused) = record(trace, 8, present(1)) { return 5 }
    if trace != 0 { return 6 }
    var cursor = 0
    var total = 0
    while let present(value) = record(trace, 1, present(cursor)), value < 3 {
        cursor += 1
        if cursor == 2 { continue }
        total += value
    }
    if cursor != 3 || total != 2 || trace != 1111 { return 7 }
    if wide(true) != 1 || wide(false) != 2 { return 8 }
    if earlier_exit(true) != 42 || earlier_exit(false) != 7 { return 9 }
    0
}
