
interface Code { fn code(): i32; }
type Box<T> { value: T }
type Tag<const N: i32> {}
impl<T> Box<T> implements Code where T = i32 {
    fn code(): i32 { self.value }
}
impl<T> Box<T> implements Code where T = bool {
    fn code(): i32 { if self.value { 42 } else { 0 } }
}
impl<const N: i32> Tag<N> implements Code where [i32;N] = [i32;3] {
    fn code(): i32 { N }
}
impl<const N: i32> Tag<N> implements Code where [i32;N] = [i32;4] {
    fn code(): i32 { N }
}
fn main(): i32 {
    let number = Box(42)
    let flag = Box(true)
    let three = Tag::<3>()
    let four = Tag::<4>()
    if number.code() == 42 && flag.code() == 42 &&
       three.code() == 3 && four.code() == 4 { 0 } else { 1 }
}
