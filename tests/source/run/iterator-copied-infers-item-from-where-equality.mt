import core.iter.Iterator

// `copied` and `cloned` bind `T` and region `r` only through
// `where Self.Item = read T from r`.
fn main(): i32 {
    let values = [4i32, 6i32]
    var copied = values.iter().copied()
    match copied.next() {
        present(first) => { if first != 4 { return 1 } },
        none => { return 2 }
    }
    let sum = values.iter().cloned().fold(0, fn(take total: i32, take value: i32): i32 {
        total + value
    })
    if sum != 10 { return 3 }
    0
}
