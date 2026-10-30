enum ParseError {
    Negative
}

fn invalid(value: i32) {
    if value < 0 {
        throw ParseError.Negative
    }
    value
}

fn main(): i32 {
    0
}
