// expect-exit: trap
// flags: --overflow-checks on
fn main(): i32 {
    let _ = core.hint.black_box(251u8).next_multiple_of(10u8)
    0
}
