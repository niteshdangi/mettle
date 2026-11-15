// expect-error: type 17:5 unsatisfied interface obligation
// expect-error: type 18:5 unsatisfied interface obligation
// expect-error: type 19:5 unsatisfied interface obligation
// expect-error: type 20:5 unsatisfied interface obligation
// expect-error: type 21:5 unsatisfied interface obligation
// expect-error: name 23:13 unresolved or inaccessible function 'next_back'
// expect-error: name 25:13 unresolved or inaccessible function 'next_back'
// expect-error: name 29:17 unresolved or inaccessible function 'next_back'
// expect-error: name 33:17 unresolved or inaccessible function 'next_back'
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
    var terminated = "ababa".split_terminator("aba")
    let _ = terminated.next_back()
    var reverse_terminated = "ababa".rsplit_terminator("aba")
    let _ = reverse_terminated.next_back()
    var mutable = [1, 0, 2, 0, 3]
    {
        var limited = mutable.splitn_mut(2usize, fn(read x: i32): bool { x == 0 })
        let _ = limited.next_back()
    }
    {
        var limited = mutable.rsplitn_mut(2usize, fn(read x: i32): bool { x == 0 })
        let _ = limited.next_back()
    }
    0
}
