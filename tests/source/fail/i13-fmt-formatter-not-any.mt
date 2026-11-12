// expect-error: type 6:5 unsatisfied interface obligation: no implementation of 'any Any' is available for 'Formatter'
// Formatter borrows an erased sink and is not a static value, so it has no Any implementation.
import core.any.Any
fn any_ok<T: Any>(): Unit {}
fn main(): i32 {
    any_ok<core.fmt.Formatter<region static>>()
    0
}
