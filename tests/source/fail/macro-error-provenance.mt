// expect-error: type 4:9 expected i32, found bool
macro wrong {
    () => {
        let value: i32 = true
    };
}
fn main(): i32 {
    wrong!()
    0
}
