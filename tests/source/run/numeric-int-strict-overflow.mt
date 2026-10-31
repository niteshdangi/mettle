// expect-exit: trap
// profiles: debug release

fn main() {
    let result = 127i8.strict_add(1i8)
    core.hint.black_box(result)
    ()
}
