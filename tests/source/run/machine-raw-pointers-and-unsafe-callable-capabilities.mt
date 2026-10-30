
unsafe fn increment(value: ptr<mut i64>) { *value += 1 }
fn identity<T>(value: ptr<mut T>): ptr<mut T> { value }
fn main() {
    var value = 40i64
    let pointer = identity(mut value as ptr<mut i64>)
    unsafe {
        *pointer += 1
        let operation: unsafe fn(ptr<mut i64>): Unit = increment
        operation(pointer)
    }
    if value == 42i64 { 0 } else { 1 }
}
