
interface Choose { fn choose(): i32; }
type Value {
    value: i32
    mut fn choose(): i32 { self.value += 1; 1 }
}
impl Value implements Choose { fn choose(): i32 { 2 } }
type Native { fn choose(): i32 { 3 } }
impl read Native { fn choose(): i32 { 4 } }
fn main() {
    let value = Value(0)
    let native = Native()
    let view = read native
    if value.choose() == 2 && view.choose() == 4 { 0 } else { 1 }
}
