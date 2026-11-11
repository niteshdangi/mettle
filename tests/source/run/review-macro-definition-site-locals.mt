const VALUE: i32 = 1
macro get { () => { VALUE }; }
macro captured { () => { $capture(VALUE) }; }
macro bound { () => { { let VALUE = 3; VALUE } }; }
macro helper {
    () => {
        fn identity<T>(take value: T): T { value }
        fn preserve<F: core.future.Future<Output = i32>>(take future: F): F {
            future
        }
    };
}
helper!()
fn main(): i32 {
    let VALUE = 2
    if get!() == 1 && captured!() == 2 && bound!() == 3 && identity(4) == 4 {
        0
    } else { 1 }
}
