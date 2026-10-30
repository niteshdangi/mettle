// expect-error: ownership 9:5 cannot move out of a borrowed place

interface Choose { fn choose(): i32; }
type Value { take fn choose(): i32 { 1 } }
impl Value implements Choose { fn choose(): i32 { 2 } }
fn main() {
    let value = Value()
    let borrowed = read value
    borrowed.choose()
}
