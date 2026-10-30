
enum Opt<T> { Nothing, Just(T) }
fn nothing<T>(): Opt<T> { Opt.Nothing }
fn main(): i32 {
    let a: Opt<i32> = Opt.Nothing
    let b = Opt<i32>.Nothing
    let c: Opt<i32> = nothing<i32>()
    match a { Opt.Nothing => 0, Opt.Just(x) => x }
}
