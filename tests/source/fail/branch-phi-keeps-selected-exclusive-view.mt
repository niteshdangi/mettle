// expect-error: ownership 6:5 live exclusive loan
fn check(take choose: bool): i32 {
    var first = 0
    var second = 0
    let selected = if choose { mut first } else { mut second }
    first = 1
    *selected
}
fn main(): i32 { check(true) }
