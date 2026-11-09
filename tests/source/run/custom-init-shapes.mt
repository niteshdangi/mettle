type Number {
    value: i32
    init(value: i32, extra: i32 = 2) { self.value = value + extra }
}
extend Number {
    init(left: i32, right: i32, extra: i32) { self.value = left + right + extra }
}

type Owned { value: i32 }
type Choice<T> { value: i32 }
extend<T: Copy> Choice<T> {
    init(value: i32) { self.value = value }
}
extend Choice<Owned> {
    init(value: i32) { self.value = value + 1 }
}

type Callback<T> {
    operation: fn(i32): T
    init(take operation: fn(i32): T) { self.operation = take operation }
}

fn main(): i32 {
    let a = Number(40)
    let b = Number(extra: 1, value: 41)
    let c = Number(right: 20, left: 21, extra: 1)
    let d = Choice<i32>(42)
    let e = Choice<Owned>(41)
    let f = Callback(fn(value: i32): i32 { value + 1 })
    let sum = a.value + b.value + c.value + d.value + e.value + f.operation(41)
    if sum == 6 * 42 { 0 } else { 1 }
}
