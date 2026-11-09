// expect-error: ownership 12:5 live read loan

copy type Reader<region r> { value: read i32 from r }
fn set(mut reader: Reader, read source: i32, flag: bool) {
    if flag { reader.value = read source }
}
fn main() {
    var first = 40
    let second = 42
    var reader = Reader(read first)
    set(reader, second, false)
    first = 0
    *reader.value
}
