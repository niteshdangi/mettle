copy enum Value { First(i32); Second(i32) }

fn inspect(value: Value): i32 {
    let outer = 20
    match (outer, value) {
        (prefix, Value.First(number) | Value.Second(number)) => {
            let nested = match value {
                Value.First(inner) | Value.Second(inner) => inner
            }
            prefix + number + nested
        }
    }
}

fn main(): i32 {
    if inspect(Value.First(11)) == 42 && inspect(Value.Second(11)) == 42 {
        0
    } else {
        1
    }
}
