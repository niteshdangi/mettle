
copy type Reader<region r> { value: read i32 from r }
fn main() {
    var value = 40
    let reader = Reader(read value)
    let copied = reader
    let observed = *copied.value
    value = 42
    if observed == 40 && value == 42 { 0 } else { 1 }
}
