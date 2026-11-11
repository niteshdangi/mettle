fn value(): i32 {
    var values = [0]
    values[{ return false; }] = { return 7; }
}
fn main(): i32 { value() - 7 }
