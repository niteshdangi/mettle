// expect-exit: trap
// profiles: debug release

fn main(): i32 {
    let result = 2i8.strict_pow(7u32)
    core.hint.black_box(result)
    0
}
