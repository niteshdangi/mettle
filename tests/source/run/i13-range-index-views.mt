// profiles: debug release
fn main(): i32 {
    var values = [1, 2, 3, 4, 5]
    let middle: read [i32] = read values[1usize..4usize]
    if middle.len() != 3usize || middle[0usize] != 2 { return 1 }
    let tail: read [i32] = read values[3usize..]
    if tail.len() != 2usize || tail[1usize] != 5 { return 2 }
    let edit: mut [i32] = mut values[..2usize]
    edit[0usize] = 9
    if values[0usize] != 9 { return 3 }

    let text = "hello"
    let piece: read core.text.Text = read text[1usize..3usize]
    if piece != "el" { return 4 }
    0
}
