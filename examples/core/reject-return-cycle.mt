fn first() {
    second()
}

fn second() {
    first()
}

fn main(): i32 {
    first()
}
