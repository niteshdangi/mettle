fn value() { 1 }
fn wide() { 2i64 }
fn main(): i32 {
    let first: i32 = value()
    let second: i64 = wide()
    if first == 1 && second == 2i64 { 0 } else { 1 }
}
