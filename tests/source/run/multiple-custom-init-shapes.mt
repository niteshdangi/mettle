type Number {
    value: i32
    init(value: i32) { self.value = value }
}

extend Number {
    init(left: i32, right: i32, extra: i32 = 1) {
        self.value = left + right + extra
    }
}

fn main(): i32 {
    let first = Number(value: 42)
    let second = Number(right: 20, left: 21)
    if first.value == 42 && second.value == 42 { 0 } else { 1 }
}
