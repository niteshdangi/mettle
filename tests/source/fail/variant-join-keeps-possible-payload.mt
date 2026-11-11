// expect-error: ownership 6:5 live exclusive loan
fn keep(take populated: bool): i32 {
    var value = 0
    let slot = if populated { present(mut value) } else { none }
    match read slot { present(view) => {}, none => {} }
    value = 1
    match take slot { present(view) => *view, none => 0 }
}
fn main(): i32 { keep(true) }
