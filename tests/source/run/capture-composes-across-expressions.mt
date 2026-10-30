
copy enum Error { Bad }
fn value(input: i32): i32 throws Error { if input < 0 { throw Error.Bad }; input }
fn main() {
    let first = capture (value(20) + value(22))
    let second = capture { let first = try value(20); first + value(-1) }
    let answer = match first { success(answer) => answer, failure(_) => 0 }
    let failed = match second { success(_) => false, failure(Error.Bad) => true }
    if answer == 42 && failed { 0 } else { 1 }
}
