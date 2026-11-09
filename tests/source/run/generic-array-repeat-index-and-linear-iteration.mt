
type Owned { value: i32 }
fn make<const N: i32>(value: i32): [i32;N] { [value;N] }
fn sum<const N: i32>(read values: [i32;N]): i32 {
    var total = 0
    for value in values { total += value }
    total
}
fn increment<const N: i32>(mut values: [i32;N]): Unit {
    for value in mut values { value += 1 }
}
fn first<const N: i32>(take values: [Owned;N]): i32 {
    var answer = 0
    for value in take values { answer = value.value; break }
    answer
}
fn main(): i32 {
    var values = make<2>(20)
    increment(values)
    if sum(values) == 42 && values[0] == 21 && sum<0>([]) == 0 &&
       first([Owned(42),Owned(1)]) == 42 { 0 } else { 1 }
}
