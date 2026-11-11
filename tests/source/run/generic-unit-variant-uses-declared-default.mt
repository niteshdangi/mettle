enum Defaulted<T = i32> { Empty; Value(T) }
fn main(): i32 {
    let value = Defaulted.Empty
    match take value {
        Defaulted.Empty => 0,
        Defaulted.Value(_) => 1,
    }
}
