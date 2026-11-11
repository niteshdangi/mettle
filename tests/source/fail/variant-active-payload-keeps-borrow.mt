// expect-error: ownership 7:13 live exclusive loan
fn main(): i32 {
    var value = 0
    let slot = present(mut value)
    match take slot {
        present(view) => {
            value = 1
            *view
        },
        none => 0
    }
}
