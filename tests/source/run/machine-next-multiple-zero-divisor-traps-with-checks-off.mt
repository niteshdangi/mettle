// expect-exit: trap
// flags: --overflow-checks off
fn main(): i32 {
    let _ = core.hint.black_box(7u8).next_multiple_of(0u8)
    0
}
