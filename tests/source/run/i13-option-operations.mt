// expect-exit: 0
// profiles: debug release
// Evidence for the V1 Option operation subset on the native optional `T?`
// (Rust Option -> `T?`, Some -> present, None -> none). Each operation is
// called on present and absent inputs and its result checked. Pinned views
// (as_pin_ref/as_pin_mut) are covered by i13-option-pin-projections.mt.

import core.option
import core.text.Text

fn some(value: i32): i32? { present(value) }
fn nothing(): i32? { none }

fn checks_construction_and_queries(): i32 {
    let present_value: i32? = present(4)
    let absent: i32? = none
    if !present_value.is_present() || absent.is_present() { return 10 }
    if present_value.is_none() || !absent.is_none() { return 11 }
    if !some(5).is_present_and(fn(value: i32): bool { value == 5 }) { return 12 }
    if some(5).is_present_and(fn(value: i32): bool { value == 6 }) { return 13 }
    if nothing().is_present_and(fn(value: i32): bool { true }) { return 14 }
    if !nothing().is_none_or(fn(value: i32): bool { false }) { return 15 }
    if !some(2).is_none_or(fn(value: i32): bool { value == 2 }) { return 16 }
    if some(2).is_none_or(fn(value: i32): bool { value == 3 }) { return 17 }
    0
}

fn checks_views(): i32 {
    var value: i32? = present(9)
    match value.as_view() { present(view) => { if *view != 9 { return 20 } }, none => { return 21 } }
    if nothing().as_view().is_present() { return 22 }
    match take value.as_mut() { present(view) => { *view = 10 }, none => { return 23 } }
    if value != present(10) { return 24 }
    let boxed: (heap i32)? = present(heap 5)
    match boxed.as_deref() { present(view) => { if *view != 5 { return 25 } }, none => { return 26 } }
    let no_box: (heap i32)? = none
    if no_box.as_deref().is_present() { return 37 }
    if value.as_slice().len() != 1usize || value.as_slice()[0usize] != 10 { return 27 }
    if nothing().as_slice().len() != 0usize { return 28 }
    value.as_mut_slice()[0usize] = 11
    if value != present(11) { return 29 }
    var empty: i32? = none
    if empty.as_mut_slice().len() != 0usize { return 30 }
    var count = 0usize
    var sum = 0
    for item in value.iter() { count = count + 1usize; sum = sum + *item }
    if count != 1usize || sum != 11 { return 31 }
    if empty.iter().next().is_present() { return 32 }
    for item in value.iter_mut() { *item = *item + 1 }
    if value != present(12) { return 33 }
    if empty.iter_mut().next().is_present() { return 34 }
    let doubled = value.iter().rev().next()
    match doubled { present(view) => { if *view != 12 { return 35 } }, none => { return 36 } }
    0
}

fn checks_extraction(): i32 {
    if some(3).or_panic() != 3 || some(4).or_panic("present") != 4 { return 40 }
    if some(5).or(0) != 5 || nothing().or(6) != 6 { return 41 }
    if nothing().or_else(fn(): i32 { 7 }) != 7 { return 42 }
    if some(1).or_else(fn(): i32 { 7 }) != 1 { return 43 }
    if nothing().or_default() != 0 || some(8).or_default() != 8 { return 44 }
    if unsafe { some(9).unwrap_unchecked() } != 9 { return 45 }
    0
}

fn checks_transformations(): i32 {
    if some(2).map(fn(value: i32): i32 { value * 3 }) != present(6) { return 50 }
    if nothing().map(fn(value: i32): i32 { value * 3 }).is_present() { return 51 }
    if some(2).map_or(0, fn(value: i32): i32 { value + 1 }) != 3 { return 52 }
    if nothing().map_or(5, fn(value: i32): i32 { value + 1 }) != 5 { return 53 }
    if nothing().map_or_else(fn(): i32 { 8 }, fn(value: i32): i32 { value }) != 8 { return 54 }
    if some(4).map_or_else(fn(): i32 { 8 }, fn(value: i32): i32 { value * 2 }) != 8 { return 55 }
    if nothing().map_or_default(fn(value: i32): i32 { value + 1 }) != 0 { return 56 }
    if some(4).map_or_default(fn(value: i32): i32 { value + 1 }) != 5 { return 57 }
    if some(4).filter(fn(read value: i32): bool { value > 3 }) != present(4) { return 58 }
    if some(2).filter(fn(read value: i32): bool { value > 3 }).is_present() { return 59 }
    var inspect_calls = 0
    let inspected = some(6).inspect(fn(read value: i32): Unit {
        inspect_calls += 1
        if value != 6 { core.panic.panic("inspect saw the wrong payload") }
    })
    if inspected != present(6) || inspect_calls != 1 { return 60 }
    if nothing().inspect(fn(read value: i32): Unit { core.panic.panic("inspect ran on none") }).is_present() { return 64 }
    let nested: (i32?)? = present(present(3))
    if nested.flatten() != present(3) { return 61 }
    let outer_none: (i32?)? = none
    if outer_none.flatten().is_present() { return 62 }
    let view_source: i32? = present(14)
    let copied = view_source.as_view().copied()
    let cloned = view_source.as_view().cloned()
    if copied != present(14) || cloned != present(14) { return 63 }
    0
}

fn checks_combinators(): i32 {
    if some(1).and(present(true)) != present(true) { return 70 }
    if nothing().and(present(true)).is_present() { return 71 }
    if some(1).and_then(fn(value: i32): i32? { present(value + 1) }) != present(2) { return 72 }
    if some(1).and_then(fn(value: i32): i32? { none }).is_present() { return 73 }
    if some(1).or_present(present(2)) != present(1) || nothing().or_present(present(2)) != present(2) { return 74 }
    if nothing().or_present_with(fn(): i32? { present(3) }) != present(3) { return 75 }
    if some(1).or_present_with(fn(): i32? { present(3) }) != present(1) { return 76 }
    if some(1).xor(none) != present(1) || nothing().xor(present(2)) != present(2) { return 77 }
    if some(1).xor(present(2)).is_present() || nothing().xor(none).is_present() { return 78 }
    match some(1).zip(present(true)) {
        present((left, right)) => { if left != 1 || !right { return 79 } },
        none => { return 80 }
    }
    if nothing().zip(present(true)).is_present() { return 81 }
    let pair: (i32, bool)? = present((5, false))
    let (left, right) = pair.unzip()
    if left != present(5) || right != present(false) { return 82 }
    let no_pair: (i32, bool)? = none
    let (left_none, right_none) = no_pair.unzip()
    if left_none.is_present() || right_none.is_present() { return 83 }
    0
}

fn checks_outcomes(): i32 {
    match some(3).or_failure(false) { success(value) => { if value != 3 { return 90 } }, failure(_) => { return 91 } }
    match nothing().or_failure(false) { success(_) => { return 92 }, failure(error) => { if error { return 93 } } }
    match nothing().or_failure_with(fn(): i32 { 9 }) { success(_) => { return 94 }, failure(error) => { if error != 9 { return 95 } } }
    let transposed_source: (Outcome<i32, bool>)? = present(success(4))
    match transposed_source.transpose() {
        success(inner) => { if inner != present(4) { return 96 } },
        failure(_) => { return 97 }
    }
    let absent_outcome: (Outcome<i32, bool>)? = none
    match absent_outcome.transpose() {
        success(inner) => { if inner.is_present() { return 98 } },
        failure(_) => { return 99 }
    }
    0
}

fn checks_in_place(): i32 {
    var slot: i32? = none
    *slot.get_or_insert(1) += 1
    if slot != present(2) { return 110 }
    if *slot.get_or_insert(9) != 2 { return 111 }
    var lazy: i32? = none
    if *lazy.get_or_insert_with(fn(): i32 { 5 }) != 5 { return 112 }
    var defaulted: i32? = none
    if *defaulted.get_or_insert_default() != 0 { return 113 }
    var inserted: i32? = present(1)
    *inserted.insert(7) += 1
    if inserted != present(8) { return 114 }
    var taken: i32? = present(3)
    if taken.`take`() != present(3) || taken.is_present() { return 115 }
    var conditional: i32? = present(4)
    if conditional.take_if(fn(mut value: i32): bool { value == 5 }).is_present() { return 116 }
    if conditional.take_if(fn(mut value: i32): bool { value == 4 }) != present(4) { return 117 }
    if conditional.is_present() { return 118 }
    var replaced: i32? = present(1)
    if replaced.replace(2) != present(1) || replaced != present(2) { return 119 }
    var boxed: (heap i32)? = present(heap 3)
    match take boxed.as_deref_mut() { present(view) => { *view = *view + 1 }, none => { return 121 } }
    match boxed.as_deref() { present(view) => { if *view != 4 { return 120 } }, none => { return 122 } }
    var no_box: (heap i32)? = none
    if no_box.as_deref_mut().is_present() { return 123 }
    0
}

fn main(): i32 {
    var code = checks_construction_and_queries()
    if code != 0 { return code }
    code = checks_views()
    if code != 0 { return code }
    code = checks_extraction()
    if code != 0 { return code }
    code = checks_transformations()
    if code != 0 { return code }
    code = checks_combinators()
    if code != 0 { return code }
    code = checks_outcomes()
    if code != 0 { return code }
    checks_in_place()
}
