
copy type Reader<region r> { value: read i32 from r }
fn set(mut reader: Reader, read source: i32, flag: bool) {
    if flag { reader.value = read source } else { reader.value = read source }
}
fn forward(mut reader: Reader, read source: i32) { set(reader, source, false) }
fn main() {
    var first = 40
    let second = 42
    var reader = Reader(read first)
    forward(reader, second)
    first = 0
    if *reader.value == 42 && first == 0 { 0 } else { 1 }
}
