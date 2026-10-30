enum ParseError {
    Negative
}

fn accept_nonnegative(value: i32): i32 throws ParseError {
    if value < 0 {
        throw ParseError.Negative
    }
    value
}

fn main(): i32 {
    let result: i32 throws ParseError = capture accept_nonnegative(-1)
    match take result {
        success(_) => 1,
        failure(ParseError.Negative) => 0
    }
}
