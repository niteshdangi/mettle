fn double(value: i32) {
    value * 2
}

fn explicit_double(value: i32): i32 {
    value * 2
}

fn choose(flag: bool) {
    if flag {
        return 40
    }
    42
}

fn recursive_count(value: i32) {
    if value == 0 {
        0
    } else {
        recursive_count(value - 1) + 1
    }
}

fn identity<T>(value: take T) {
    value
}

fn inferred_unit() {
}

fn explicit_unit(): Unit {
    ()
}

fn discard() {
    42;
}

fn early_unit(flag: bool) {
    if flag {
        return
    }
}

fn main() {
    let first: Unit = inferred_unit()
    let second: Unit = explicit_unit()
    let third: Unit = discard()
    let fourth: Unit = early_unit(true)
    let literal: Unit = ()
    let copied = literal
    let original = literal
    if double(21) == 42 && explicit_double(21) == 42 &&
        choose(false) == 42 && choose(true) == 40 &&
        recursive_count(3) == 3 && identity(42) == 42 {
        0
    } else {
        1
    }
}
