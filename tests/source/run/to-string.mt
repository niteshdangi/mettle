import alloc.string.ToString

fn main(): i32 {
    let text = "ab"
    let owned = text.to_string()
    if owned.len() != 2usize || owned.as_bytes()[0usize] != 97u8 { return 1 }
    0
}
