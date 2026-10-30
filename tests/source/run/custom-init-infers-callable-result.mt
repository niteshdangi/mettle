type Callback<T> {
    operation: fn(i32): T
    init(operation: take fn(i32): T) { self.operation = take operation }
}

fn main(): i32 {
    let callback = Callback(fn(value: i32): i32 { value + 1 })
    callback.operation(41) - 42
}
