
copy type Reader<region r> { value: read i32 from r }
type Marker { drop {} }
type Bundle<region r> { reader: Reader<region r>; marker: Marker }
fn main() {
    var value = 40
    var bundle = Bundle(Reader(read value), Marker())
    let observed = *bundle.reader.value
    value = 42
    bundle = Bundle(Reader(read value), Marker())
    if observed == 40 { 0 } else { 1 }
}
