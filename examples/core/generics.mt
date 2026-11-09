type Counter {
    value: i32
}

fn inspect<T>(value: T): Unit {
}

fn duplicate<T: Copy>(value: T): T {
    value
}

fn identity<T>(take value: T): T {
    value
}

fn main(): i32 {
    let number = 42
    inspect(number)
    let copied = duplicate(number)
    let first = Counter(copied)
    let second = identity(first)
    if number == 42 && second.value == 42 {
        0
    } else {
        1
    }
}
