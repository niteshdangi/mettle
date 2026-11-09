
copy type Reader<region r> { value: read i32 from r }
fn set(mut reader: Reader, read source: i32) { reader.value = read source }
fn forward(mut reader: Reader, read source: i32) { set(reader, source) }
fn main() {
    let first = 40
    let second = 42
    var reader = Reader(read first)
    forward(reader, second)
    if *reader.value == 42 { 0 } else { 1 }
}
