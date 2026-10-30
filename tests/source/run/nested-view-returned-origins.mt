
copy type Payload<region r> { value: read i32 from r }
copy type Reader<region r> { inner: read Payload from r }
fn get(reader: read Reader): read i32 from reader { reader.inner.value }
fn main() {
    let value = 42
    let payload = Payload(read value)
    let reader = Reader(read payload)
    if *get(reader) == 42 { 0 } else { 1 }
}
