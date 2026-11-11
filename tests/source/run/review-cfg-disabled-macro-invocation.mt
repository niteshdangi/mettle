@cfg(true)
macro zero { () => { 0 }; }
@cfg(false)
fn disabled(): i32 { zero!(1) }
@cfg(false)
macro ignored { this is not a matcher }
@cfg(false)
module ignored_module {
    fn disabled(): i32 { zero!(2) }
}
@cfg(false)
fn multiline<T, U>()
{
    zero!(3)
}
@cfg(false)
const DISABLED: i32 = if true { zero!(4) } else { zero!(5) }
macro generated {
    () => {
        @cfg(false)
        fn generated_disabled(): i32 { zero!(6) }
        fn generated_value(): i32 { zero!() }
    };
}
generated!()
fn main(): i32 { generated_value() }
