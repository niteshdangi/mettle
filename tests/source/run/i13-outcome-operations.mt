// expect-exit: 0
// profiles: debug release
// Evidence for the V1 Result operation subset on the stored outcome
// `Outcome<T, E>` (Rust Result -> `Outcome<T, E>`, Ok -> success, Err ->
// failure, is_ok/is_err -> is_success/is_failure). Each operation is called on
// success and failure inputs and its result checked. copied/cloned are in
// i13-outcome-copied-cloned.mt.

import core.outcome
import core.option

fn ok(value: i32): (Outcome<i32, i32>) { success(value) }
fn err(error: i32): (Outcome<i32, i32>) { failure(error) }

fn checks_queries(): i32 {
    if !ok(1).is_success() || err(1).is_success() { return 10 }
    if ok(1).is_failure() || !err(1).is_failure() { return 11 }
    if !ok(2).is_ok_and(fn(value: i32): bool { value == 2 }) { return 12 }
    if ok(2).is_ok_and(fn(value: i32): bool { value == 3 }) || err(2).is_ok_and(fn(value: i32): bool { true }) { return 13 }
    if !err(4).is_err_and(fn(error: i32): bool { error == 4 }) { return 14 }
    if err(4).is_err_and(fn(error: i32): bool { error == 5 }) || ok(4).is_err_and(fn(error: i32): bool { true }) { return 15 }
    if ok(3).ok() != present(3) || err(3).ok().is_present() { return 16 }
    if err(3).err() != present(3) || ok(3).err().is_present() { return 17 }
    0
}

fn checks_views(): i32 {
    var value: (Outcome<i32, i32>) = success(9)
    match value.as_ref() { success(view) => { if *view != 9 { return 20 } }, failure(_) => { return 21 } }
    match err(8).as_ref() { success(_) => { return 22 }, failure(view) => { if *view != 8 { return 23 } } }
    match take value.as_mut() { success(view) => { *view = 10 }, failure(_) => { return 24 } }
    if value.unwrap() != 10 { return 25 }
    var failed: (Outcome<i32, i32>) = failure(1)
    match take failed.as_mut() { success(_) => { return 26 }, failure(view) => { *view = 2 } }
    if failed.unwrap_err() != 2 { return 27 }
    var boxed: (Outcome<heap i32, i32>) = success(heap 5)
    match boxed.as_deref() { success(view) => { if *view != 5 { return 28 } }, failure(_) => { return 29 } }
    match take boxed.as_deref_mut() { success(view) => { *view = 6 }, failure(_) => { return 30 } }
    match boxed.as_deref() { success(view) => { if *view != 6 { return 31 } }, failure(_) => { return 32 } }
    let boxed_failure: (Outcome<heap i32, i32>) = failure(3)
    match boxed_failure.as_deref() { success(_) => { return 33 }, failure(view) => { if *view != 3 { return 34 } } }
    var iterated: (Outcome<i32, i32>) = success(4)
    var count = 0usize
    for item in iterated.iter() { count = count + 1usize; if *item != 4 { return 35 } }
    if count != 1usize { return 36 }
    for item in iterated.iter_mut() { *item = *item * 2 }
    match iterated.as_ref() { success(view) => { if *view != 8 { return 37 } }, failure(_) => { return 37 } }
    var failed_iter: (Outcome<i32, i32>) = failure(0)
    if failed_iter.iter().next().is_present() || failed_iter.iter_mut().next().is_present() { return 38 }
    match iterated.iter().rev().next() { present(view) => { if *view != 8 { return 39 } }, none => { return 40 } }
    0
}

fn checks_extraction(): i32 {
    if ok(1).unwrap() != 1 || ok(2).expect("success") != 2 { return 50 }
    if err(3).unwrap_err() != 3 || err(4).expect_err("failure") != 4 { return 51 }
    if ok(5).unwrap_or(0) != 5 || err(5).unwrap_or(6) != 6 { return 52 }
    if err(7).unwrap_or_else(fn(error: i32): i32 { error + 1 }) != 8 { return 53 }
    if ok(7).unwrap_or_else(fn(error: i32): i32 { error + 1 }) != 7 { return 54 }
    if err(9).unwrap_or_default() != 0 || ok(9).unwrap_or_default() != 9 { return 55 }
    if unsafe { ok(10).unwrap_unchecked() } != 10 { return 56 }
    if unsafe { err(11).unwrap_err_unchecked() } != 11 { return 57 }
    0
}

fn checks_transformations(): i32 {
    if ok(2).map(fn(value: i32): i32 { value * 3 }).unwrap() != 6 { return 60 }
    if err(2).map(fn(value: i32): i32 { value * 3 }).unwrap_err() != 2 { return 61 }
    if err(2).map_err(fn(error: i32): i32 { error + 10 }).unwrap_err() != 12 { return 62 }
    if ok(2).map_err(fn(error: i32): i32 { error + 10 }).unwrap() != 2 { return 63 }
    if ok(2).map_or(0, fn(value: i32): i32 { value + 1 }) != 3 || err(2).map_or(5, fn(value: i32): i32 { value }) != 5 { return 64 }
    if err(2).map_or_else(fn(error: i32): i32 { error * 4 }, fn(value: i32): i32 { value }) != 8 { return 65 }
    if ok(2).map_or_else(fn(error: i32): i32 { error * 4 }, fn(value: i32): i32 { value + 7 }) != 9 { return 66 }
    if err(2).map_or_default(fn(value: i32): i32 { value + 1 }) != 0 { return 67 }
    if ok(2).map_or_default(fn(value: i32): i32 { value + 1 }) != 3 { return 68 }
    let inspected = ok(6).inspect(fn(read value: i32): Unit {
        if value != 6 { core.panic.panic("inspect saw the wrong payload") }
    })
    if inspected.unwrap() != 6 { return 69 }
    let skipped = err(6).inspect(fn(read value: i32): Unit { core.panic.panic("inspect ran on failure") })
    if skipped.unwrap_err() != 6 { return 70 }
    let inspected_error = err(7).inspect_err(fn(read error: i32): Unit {
        if error != 7 { core.panic.panic("inspect_err saw the wrong error") }
    })
    if inspected_error.unwrap_err() != 7 { return 71 }
    let skipped_error = ok(7).inspect_err(fn(read error: i32): Unit { core.panic.panic("inspect_err ran on success") })
    if skipped_error.unwrap() != 7 { return 72 }
    let nested: (Outcome<(Outcome<i32, i32>), i32>) = success(success(3))
    if nested.flatten().unwrap() != 3 { return 73 }
    let nested_inner: (Outcome<(Outcome<i32, i32>), i32>) = success(failure(4))
    if nested_inner.flatten().unwrap_err() != 4 { return 74 }
    let nested_outer: (Outcome<(Outcome<i32, i32>), i32>) = failure(5)
    if nested_outer.flatten().unwrap_err() != 5 { return 75 }
    let transposed: (Outcome<i32?, i32>) = success(present(1))
    match transposed.transpose() { present(inner) => { if inner.unwrap() != 1 { return 76 } }, none => { return 77 } }
    let empty: (Outcome<i32?, i32>) = success(none)
    if empty.transpose().is_present() { return 78 }
    let failed: (Outcome<i32?, i32>) = failure(2)
    match failed.transpose() { present(inner) => { if inner.unwrap_err() != 2 { return 79 } }, none => { return 80 } }
    0
}

fn checks_combinators(): i32 {
    let next: (Outcome<bool, i32>) = success(true)
    if !ok(1).and(next).unwrap() { return 90 }
    let unused: (Outcome<bool, i32>) = success(true)
    if err(1).and(unused).unwrap_err() != 1 { return 91 }
    if ok(1).and_then(fn(value: i32): (Outcome<i32, i32>) { success(value + 1) }).unwrap() != 2 { return 92 }
    if ok(1).and_then(fn(value: i32): (Outcome<i32, i32>) { failure(value + 5) }).unwrap_err() != 6 { return 93 }
    let fallback: (Outcome<i32, u8>) = success(2)
    if ok(1).or(fallback).unwrap() != 1 { return 94 }
    let fallback_used: (Outcome<i32, u8>) = success(2)
    if err(1).or(fallback_used).unwrap() != 2 { return 95 }
    let fallback_failed: (Outcome<i32, u8>) = failure(3u8)
    if err(1).or(fallback_failed).unwrap_err() != 3u8 { return 96 }
    if err(1).or_else(fn(error: i32): (Outcome<i32, u8>) { success(error + 1) }).unwrap() != 2 { return 97 }
    if ok(4).or_else(fn(error: i32): (Outcome<i32, u8>) { failure(0u8) }).unwrap() != 4 { return 98 }
    0
}

fn main(): i32 {
    var code = checks_queries()
    if code != 0 { return code }
    code = checks_views()
    if code != 0 { return code }
    code = checks_extraction()
    if code != 0 { return code }
    code = checks_transformations()
    if code != 0 { return code }
    checks_combinators()
}
