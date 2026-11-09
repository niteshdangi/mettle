
copy type Reader<region r> { value: read i32 from r }
type Writer<region a, region b> {
    target: mut Reader from a
    source: read i32 from b
    drop { self.target.value = self.source }
}
fn release(take writer: Writer) {}
fn main() {
    let first = 40
    let second = 42
    var reader = Reader(read first)
    release(Writer(mut reader, read second))
    if *reader.value == 42 { 0 } else { 1 }
}
