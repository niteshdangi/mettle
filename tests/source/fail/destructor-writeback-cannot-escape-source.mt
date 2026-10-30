// expect-error: ownership 12:66 live read loan

copy type Reader<region r> { value: read i32 from r }
type Writer<region a, region b> {
    target: mut Reader from a
    source: read i32 from b
    drop { self.target.value = self.source }
}
fn main() {
    let first = 42
    var reader = Reader(read first)
    { let short = 0; let writer = Writer(mut reader, read short) }
    *reader.value
}
