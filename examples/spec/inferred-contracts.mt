enum ParseError {
    Negative
}

type Counter {
    value: i32

    mut fn increment() {
        self.value += 1
    }

    fn current() {
        self.value
    }
}

pub fn accept_nonnegative(value: i32) throws ParseError {
    if value < 0 {
        throw ParseError.Negative
    }
    value
}

fn stored(value: i32): (Outcome<i32, ParseError>) {
    capture accept_nonnegative(value)
}

fn main(): i32 {
    let operation: fn(i32): i32 = fn(value: i32): i32 {
        value + 1
    }
    let inferred: fn(i32): i32 = fn(value) {
        value + 1
    }
    let callback: fn(): Unit = fn() {
        ()
    }
    let completed: Unit = callback()
    var counter = Counter(41)
    counter.increment()
    let result = stored(counter.current())
    match take result {
        success(value) => if operation(value) == 43 && inferred(value) == 43 {
            0
        } else {
            1
        },
        failure(_) => 2
    }
}
