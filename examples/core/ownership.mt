type Counter {
    value: i32
}

fn inspect(counter: Counter): i32 {
    counter.value
}

fn increment(counter: mut Counter) {
    counter.value += 1
}

fn finish(counter: take Counter): i32 {
    counter.value
}

fn main(): i32 {
    var counter = Counter(41)
    let _ = counter
    increment(counter)
    let observed = inspect(counter)
    let result = finish(counter)
    if observed == 42 && result == 42 {
        0
    } else {
        1
    }
}
