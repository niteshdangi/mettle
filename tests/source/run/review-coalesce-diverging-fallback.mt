fn value(input: i32?): i32 { input ?? { return 2; } }
fn main(): i32 {
    if value(present(7)) == 7 && value(none) == 2 { 0 } else { 1 }
}
