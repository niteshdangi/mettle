// expect-error: ownership 3:31 live read loan
fn main(): i32 {
    let view = if let owned = 42, true { read owned } else { return 0 }
    *view
}
