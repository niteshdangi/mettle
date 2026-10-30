
interface Bound { type Output; }
interface Code { fn code():i32; }
type Value {}
extend Value implements Bound { type Output = i32; }
type Box<T> { value:T }
extend<T:Bound> Box<T> implements Code where T.(Bound).Output = i32 {
    fn code():i32 { 7 }
}
fn main() { Box(Value()).code() - 7 }
