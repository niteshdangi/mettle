
copy type Reader<region r> { value: read i32 from r }
fn set(reader: mut Reader, source: read i32) { reader.value = read source }
fn forward(reader: mut Reader, source: read i32) { set(reader, source) }
fn main() {
    let first = 40
    let second = 42
    var reader = Reader(read first)
    forward(reader, second)
    if *reader.value == 42 { 0 } else { 1 }
}
