
type Tail<T: unsized> { header: i32; values: T }
fn total(read values: [i32]): i32 {
    var result = 0
    for value in values { result += value }
    result
}
fn increment(mut values: [i32]) {
    for value in mut values { value += 1 }
}
fn tail_total(read value: Tail<[i32]>): i32 { value.header + total(value.values) }
fn main() {
    var values = [20,20]
    let exclusive: mut [i32] = mut values
    let borrowed: read [i32] = exclusive
    if total(borrowed) != 40 { return 1 }
    increment(exclusive)
    let tail = Tail(2,[20,20])
    let pointer: fn(read [i32]): i32 = total
    if pointer(exclusive) == 42 && tail_total(tail) == 42 &&
        total([20,22]) == 42 { 0 } else { 1 }
}
