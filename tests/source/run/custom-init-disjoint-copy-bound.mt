type Owned { value: i32 }
type Choice<T> { value: i32 }

extend<T: Copy> Choice<T> {
    init(value: i32) { self.value = value }
}
extend Choice<Owned> {
    init(value: i32) { self.value = value + 1 }
}

fn main(): i32 {
    let first = Choice<i32>(41)
    let second = Choice<Owned>(41)
    if first.value == 41 && second.value == 42 { 0 } else { 1 }
}
