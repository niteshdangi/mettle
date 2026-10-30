// expect-error: type 4:26 expected i32, found bool
macro wrong {
    () => {
        let value: i32 = true
    };
}
fn main(): i32 {
    wrong!()
    0
}
