// expect-exit: trap
// profiles: debug release

fn main(): i32 {
    let result = 127i8.strict_add(1i8)
    core.hint.black_box(result)
    0
}
