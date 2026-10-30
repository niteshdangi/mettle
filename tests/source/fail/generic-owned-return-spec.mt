// expect-error: ownership 3:5 borrowed
fn invalid<T>(value: T): T {
    value
}

fn main(): i32 {
    0
}
