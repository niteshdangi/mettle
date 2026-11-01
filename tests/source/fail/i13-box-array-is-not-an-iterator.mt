// expect-error: type 11:5 unsatisfied interface obligation: no implementation of 'any Iterator' is available for 'heap [i32; 2]'
// expect-error: type 13:5 unsatisfied interface obligation: no implementation of 'any Iterator' is available for 'read heap [i32; 2]'
// expect-error: type 14:5 unsatisfied interface obligation: no implementation of 'any Iterator' is available for 'mut heap [i32; 2]'
// profiles: debug release
import alloc.boxed
import core.iter.Iterator

fn require_iterator<I: Iterator>(value: take I): Unit {}

fn main(): i32 {
    require_iterator(boxed.new([1i32, 2i32]))
    var owner = boxed.new([1i32, 2i32])
    require_iterator(read owner)
    require_iterator(mut owner)
    0
}
