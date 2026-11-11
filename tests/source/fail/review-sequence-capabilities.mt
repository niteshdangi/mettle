// expect-error: type 13:5 unsatisfied interface obligation
// expect-error: type 14:5 unsatisfied interface obligation
// expect-error: type 15:5 unsatisfied interface obligation
// expect-error: type 16:5 unsatisfied interface obligation
// expect-error: type 17:5 unsatisfied interface obligation
import core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator}
fn require_back<I: BidirectionalIterator>(take source: I): Unit {}
fn require_exact<I: ExactSizeIterator>(take source: I): Unit {}
fn main(): i32 {
    let values = [1, 0, 2, 0, 3]
    let xs: read [i32] = read values

    require_back(xs.splitn(2usize, fn(read x: i32): bool { x == 0 }))
    require_back("ababa".split("aba"))
    require_back("ababa".matches("aba"))
    require_back("ababa".match_indices("aba"))
    require_exact("abc".chars())
    0
}
