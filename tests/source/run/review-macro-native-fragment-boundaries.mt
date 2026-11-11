macro identity { ($value:expr) => { $value }; }
macro typed { ($value:ty {}) => { 0 }; }
fn choose<A, B>(take value: A): A { value }
fn main(): i32 {
    identity!(choose<i32, i32>(4)) + typed!(i32 {}) - 4
}
