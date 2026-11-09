// profiles: debug release
fn main(): i32 {
    if core.hint.black_box(7i32) != 7i32 { return 1 }
    0
}
