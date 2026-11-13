// expect-error: region 7:30 erased owner payload view
interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}
fn escape(): shared any Show {
    let value = 42
    shared Held(read value)
}
fn main(): i32 { 0 }
