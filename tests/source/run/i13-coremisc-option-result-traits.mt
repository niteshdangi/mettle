// profiles: debug release
// Evidence for the Option and Result trait implementations: Clone, Copy,
// comparison, Hash and Default.

import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.clone.Clone
import core.convert.From
import core.default.Default
import core.fmt
import core.fmt.{Debug, Error as FmtError, Formatter, Write}
import core.iter.{Iterable, Iterator, MutableIterable, OwnedIterable}
import core.hash.{Hash, hash_one}
import core.outcome
import core.text.Text

fn default_of<T: Default>(): T { T.(Default).default() }

type DebugCounter { count: usize }
extend DebugCounter implements Write {
    mut fn write_str(read text: Text): Unit throws FmtError { self.count += text.as_bytes().len() }
}

fn debug_len<T: Debug>(read value: T): usize throws FmtError {
    var sink = DebugCounter(0usize)
    {
        var f = fmt.formatter(mut sink, fmt.spec())
        try T.(Debug).fmt(value, mut f)
    }
    sink.count
}

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
    match take capture debug_len(read some) {
        success(length) => { if length == 0usize { return 12 } },
        failure(_) => { return 12 }
    }
    0
}

fn checks_result(): i32 {
    let ok: (Outcome<i32, i32>) = success(7i32)
    let bad: (Outcome<i32, i32>) = failure(8i32)
    let ok_again: (Outcome<i32, i32>) = success(7i32)
    let ok_nine: (Outcome<i32, i32>) = success(9i32)
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
    match take capture debug_len(read ok) {
        success(length) => { if length == 0usize { return 29 } },
        failure(_) => { return 29 }
    }
    0
}

fn checks_conversion_and_iteration(): i32 {
    let wrapped: i32? = from_value<i32?>(6i32)
    if wrapped != present(6i32) { return 40 }
    var total = 0
    let present_value: i32? = present(3i32)
    for value in take present_value { total += value }
    let success_value: (Outcome<i32, i32>) = success(4i32)
    for value in take success_value { total += value }
    let failure_value: (Outcome<i32, i32>) = failure(9i32)
    for value in take failure_value { total += value }
    let absent: i32? = none
    for value in take absent { total += value }
    if total != 7 { return 41 }
    0
}

fn from_value<T: From<i32>>(take value: i32): T { T.(From<i32>).from(value) }

alias ReadOption<region r, T> = (read T from r)?
alias MutOption<region r, T> = (mut T from r)?

fn from_read_option<region r, T>(read value: T? from r): (read T from r)? {
    ReadOption<region r, T>.(From<read (T?) from r>).from(read value)
}

fn from_mut_option<region r, T>(mut value: T? from r): (mut T from r)? {
    MutOption<region r, T>.(From<mut (T?) from r>).from(mut value)
}

fn checks_borrowed_conversion(): i32 {
    var value = present(7i32)
    match from_read_option(read value) {
        present(item) => { if *item != 7 { return 50 } },
        none => { return 50 }
    }
    match take from_mut_option(mut value) {
        present(item) => { *item += 1 },
        none => { return 51 }
    }
    match value {
        present(item) => { if item != 8 { return 52 } },
        none => { return 52 }
    }
    let absent: i32? = none
    if from_read_option(read absent).is_present() { return 53 }
    var absent_mut: i32? = none
    if from_mut_option(mut absent_mut).is_present() { return 54 }
    0
}

fn checks_borrowed_iteration(): i32 {
    let optional: i32? = present(9i32)
    var optional_total = 0i32
    for value in read optional { optional_total += *value }
    if optional_total != 9 { return 60 }

    var mutable_optional: i32? = present(10i32)
    for value in mut mutable_optional { *value += 1 }
    match mutable_optional {
        present(value) => { if value != 11 { return 61 } },
        none => { return 61 }
    }

    let outcome: (Outcome<i32, i32>) = success(12i32)
    var outcome_total = 0i32
    for value in read outcome { outcome_total += *value }
    if outcome_total != 12 { return 62 }

    var mutable_outcome: (Outcome<i32, i32>) = success(13i32)
    for value in mut mutable_outcome { *value += 1 }
    match mutable_outcome {
        success(value) => { if value != 14 { return 63 } },
        failure(_) => { return 63 }
    }

    let failed: (Outcome<i32, i32>) = failure(15i32)
    for value in read failed { outcome_total += *value }
    if outcome_total != 12 { return 64 }
    var mutable_failure: (Outcome<i32, i32>) = failure(16i32)
    for value in mut mutable_failure { *value += 1 }
    match mutable_failure {
        success(_) => { return 65 },
        failure(error) => { if error != 16 { return 65 } }
    }
    0
}

fn main(): i32 {
    let option_status = checks_option()
    if option_status != 0 { return option_status }
    let result_status = checks_result()
    if result_status != 0 { return result_status }
    let conversion_status = checks_conversion_and_iteration()
    if conversion_status != 0 { return conversion_status }
    let borrowed_status = checks_borrowed_conversion()
    if borrowed_status != 0 { return borrowed_status }
    checks_borrowed_iteration()
}
