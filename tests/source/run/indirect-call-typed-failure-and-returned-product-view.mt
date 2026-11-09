
copy type Pair { first: i32; second: i32 }
copy type Reader<region r> { value: read Pair from r }
fn expose(read reader: Reader): read Pair from reader { reader.value }
fn checked(value: i32): i32 throws i32 {
    if value < 0 { throw 7 }
    value
}
fn main(): i32 {
    let pair = Pair(20,22)
    let reader = Reader(read pair)
    let view: fn(read Reader): read Pair = expose
    let checked_pointer: fn(i32): i32 throws i32 = checked
    let result = view(reader)
    let captured = capture checked_pointer(-1)
    let failed = match captured { success(_) => false, failure(error) => error == 7 }
    if result.first + result.second == 42 && failed { 0 } else { 1 }
}
