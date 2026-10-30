type Number {
    value: i32
    init(value: i32, extra: i32 = 2) { self.value = value + extra }
}

fn main(): i32 {
    let first = Number(40)
    let second = Number(extra: 1, value: 41)
    if first.value == 42 && second.value == 42 { 0 } else { 1 }
}
