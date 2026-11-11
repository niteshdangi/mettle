// expect-error: ownership 7:19 live read loan
fn keep(take populated: bool): i32 {
    var value = 0
    let held = read value
    let slot = if populated { present(held) } else { none }
    match take slot {
        none => { value = 1; *held },
        present(view) => *view
    }
}
fn main(): i32 { keep(false) }
