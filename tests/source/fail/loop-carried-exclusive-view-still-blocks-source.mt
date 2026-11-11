// expect-error: ownership 10:13 live exclusive loan
fn main(): i32 {
    var value = 0
    var held: (mut i32)? = none
    var index = 0
    while index < 2 {
        if index == 0 {
            held = present(mut value)
        } else {
            value = 1
        }
        index += 1
    }
    match take held { present(view) => *view, none => 0 }
}
