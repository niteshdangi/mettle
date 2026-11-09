// expect-error: ownership 13:62 live read loan

copy type Reader<region r> { value: read i32 from r }
type Writer<region a, region b> {
    target: mut Reader from a
    source: read i32 from b
    drop { self.target.value = self.source }
}
fn release(take writer: Writer) {}
fn main() {
    let first = 42
    var reader = Reader(read first)
    { let short = 0; release(Writer(mut reader, read short)) }
    *reader.value
}
