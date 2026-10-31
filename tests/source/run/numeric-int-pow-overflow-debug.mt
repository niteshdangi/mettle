// expect-exit: trap
// profiles: debug

fn main(): i32 {
    let result = 2i8.pow(7u32)
    core.hint.black_box(result)
    0
}
