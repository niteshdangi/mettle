// expect-error: ownership 7:65 live read loan

copy type Reader<region r> { value: read i32 from r }
fn echo(reader: mut Reader) { reader.value = reader.value }
fn main() {
    var reader: Reader
    { let short = 42; reader = Reader(read short); echo(reader) }
    *reader.value
}
