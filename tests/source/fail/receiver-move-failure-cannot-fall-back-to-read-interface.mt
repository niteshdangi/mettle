// expect-error: ownership 9:5 cannot move out of a viewed place

interface Choose { fn choose(): i32; }
type Value { take fn choose(): i32 { 1 } }
extend Value implements Choose { fn choose(): i32 { 2 } }
fn main() {
    let value = Value()
    let borrowed = read value
    borrowed.choose()
}
