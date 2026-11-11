// expect-error: ownership 8:13 live read loan
fn first(read left: i32, take right: i32): i32 { left + right }
fn check(take choose: bool): i32 {
    var value = 0
    first(
        value,
        if choose {
            value = 1
            0
        } else { 0 }
    )
}
fn main(): i32 { check(false) }
