// expect-error: type 3:50 expected Opt<u8>, found Opt<i32>
enum Opt<T> { Some(T), Nothing }
fn main(): i32 { let s: Opt<i32> = Opt::Nothing; let t: Opt<u8> = s; 0 }
