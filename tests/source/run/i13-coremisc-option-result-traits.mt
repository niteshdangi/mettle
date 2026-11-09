// profiles: debug release
// Evidence for the Option and Result trait implementations: Clone, Copy,
// comparison, Hash and Default.

import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.clone.Clone
import core.convert.From
import core.default.Default
import core.iter.{Iterator, OwnedIterable}
import core.hash.{Hash, hash_one}
import core.outcome

fn default_of<T: Default>(): T { T.(Default).default() }

fn checks_option(): i32 {
    let some: i32? = present(4i32)
    let absent: i32? = none
    let four: i32? = present(4i32)
    let five: i32? = present(5i32)
    let none_again: i32? = none
    if some.clone() != four || absent.clone().is_present() { return 1 }
    let copied = some
    if copied != four || some != four { return 2 }
    if some == absent || absent != none_again { return 3 }
    if !(absent < some) || some < absent || !(some <= some) { return 4 }
    if !(some > absent) || !(some >= some) || absent > some { return 5 }
    if some.cmp(read five) != Ordering.Less { return 6 }
    if absent.cmp(read none_again) != Ordering.Equal { return 7 }
    let equal_order: Ordering? = present(Ordering.Equal)
    if some.partial_cmp(read four) != equal_order { return 8 }
    if hash_one(read some) != hash_one(read four) { return 9 }
    if hash_one(read some) == hash_one(read absent) { return 10 }
    let fallback: i32? = default_of<i32?>()
    if fallback.is_present() { return 11 }
    0
}

fn checks_result(): i32 {
    let ok: (i32 throws i32) = success(7i32)
    let bad: (i32 throws i32) = failure(8i32)
    let ok_again: (i32 throws i32) = success(7i32)
    let ok_nine: (i32 throws i32) = success(9i32)
    if ok.clone() != ok_again || bad.clone() == ok { return 20 }
    if ok == bad || ok != ok_again { return 21 }
    if !(ok < bad) || bad < ok { return 22 }
    if !(ok.le(read ok)) || !(bad.ge(read bad)) || ok.gt(read ok) { return 23 }
    if ok.cmp(read ok_nine) != Ordering.Less { return 24 }
    let equal_order: Ordering? = present(Ordering.Equal)
    if ok.partial_cmp(read ok_again) != equal_order { return 25 }
    if hash_one(read ok) != hash_one(read ok_again) { return 26 }
    if hash_one(read ok) == hash_one(read bad) { return 27 }
    let copied_result = ok
    if copied_result != ok_again { return 28 }
    0
}

fn checks_conversion_and_iteration(): i32 {
    let wrapped: i32? = from_value<i32?>(6i32)
    if wrapped != present(6i32) { return 40 }
    var total = 0
    let present_value: i32? = present(3i32)
    for value in take present_value { total += value }
    let success_value: (i32 throws i32) = success(4i32)
    for value in take success_value { total += value }
    let failure_value: (i32 throws i32) = failure(9i32)
    for value in take failure_value { total += value }
    let absent: i32? = none
    for value in take absent { total += value }
    if total != 7 { return 41 }
    0
}

fn from_value<T: From<i32>>(value: take i32): T { T.(From<i32>).from(value) }

fn main(): i32 {
    let option_status = checks_option()
    if option_status != 0 { return option_status }
    let result_status = checks_result()
    if result_status != 0 { return result_status }
    checks_conversion_and_iteration()
}
