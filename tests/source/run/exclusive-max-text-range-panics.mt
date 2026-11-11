// expect-exit: 101
fn main(): i32 {
    let text: read Text = "a"
    let end = !0usize
    let selected = read text[..end]
    selected.len() as i32
}
