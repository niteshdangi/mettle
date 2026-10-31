// expect-exit: trap
fn main(): i32 {
    let invalid = "a\u{e9}"[1..]
    invalid.len() as i32
}
