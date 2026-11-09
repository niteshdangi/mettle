// expect-error: name 6:9 unresolved value 'item'
fn main(): i32 {
    if let present(item) = present(1), item > 0 {
        0
    } else {
        item
    }
}
