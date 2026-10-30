// expect-error: ownership 13:5 live read loan

copy type Payload<region r> { value: read i32 from r }
copy type Reader<region r> { inner: read Payload from r }
fn get(reader: read Reader): read i32 from reader { reader.inner.value }
fn main() {
    let child: read i32
    {
        let short = 42
        let payload = Payload(read short)
        let reader = Reader(read payload)
        child = read *get(reader)
    }
    *child
}
