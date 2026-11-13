// expect-error: region 10:10 erased owner payload view
interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}
fn keep(shown: heap any Show): i32 { shown.value() }
fn main(): i32 {
    let value = 40
    keep(heap Held(read value))
}
