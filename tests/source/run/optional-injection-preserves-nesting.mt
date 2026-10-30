
fn answer(): i32? { 42 }
fn inspect(value: i32?) { value ?? 0 }
fn main() {
    let nested: i32?? = 42
    let values: [i32?; 2] = [20, 22]
    let joined = if true { present(42) } else { 0 }
    let from_nested = match nested { none => 0, present(inner) => inner ?? 0 }
    if from_nested == 42 && inspect(42) == 42 && (answer() ?? 0) == 42 &&
       (values[0] ?? 0) + (values[1] ?? 0) == 42 && (joined ?? 0) == 42 { 0 } else { 1 }
}
