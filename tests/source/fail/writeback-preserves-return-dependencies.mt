// expect-error: ownership 11:48 live read loan

copy type Reader<region r> { value: read i32 from r }
fn first(a: read i32, b: read i32): read i32 from (a, b) { read a }
fn set(target: mut Reader, a: read i32, b: read i32) {
    target.value = first(a, b)
}
fn main() {
    let value = 42
    var reader = Reader(read value)
    { let short = 0; set(reader, value, short) }
    *reader.value
}
