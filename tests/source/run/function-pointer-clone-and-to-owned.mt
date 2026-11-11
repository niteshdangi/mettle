// profiles: debug release
import core.borrow.ToOwned
import core.clone.Clone

type Value { number: i32 }

fn consume(take value: Value): i32 { value.number }
fn inspect(read value: Value): i32 { value.number }
fn replacement(take value: Value): i32 { value.number + 1 }
fn answer(): i32 { 42 }
fn increment(mut value: i32, take amount: i32): i32 {
    value += amount
    value
}
fn identity<region r>(read value: i32 from r): read i32 from r { read value }
copy enum Failure { Rejected }
fn may_fail(take rejected: bool): i32 throws Failure {
    if rejected { throw Failure.Rejected }
    9
}
extern "C" fn foreign_increment(value: i32): i32 { value + 1 }

fn duplicate<F: Clone>(read callback: F): F { callback.clone() }

fn main(): i32 {
    let consuming = consume
    var consuming_copy = duplicate(consuming)
    let consuming_owned = consuming.to_owned()
    assert(consuming(Value(1)) == 1, "original consuming function")
    assert(consuming_copy(Value(2)) == 2, "clone consumes a non-Copy argument")
    assert(consuming_owned(Value(3)) == 3, "owned consuming function")
    let other = replacement
    consuming_copy.clone_from(other)
    assert(consuming_copy(Value(4)) == 5, "clone_from replaces the function")
    assert(consuming(Value(4)) == 4, "clone_from preserves the original")
    let reading = inspect
    let reading_copy = duplicate(reading)
    let reading_owned = reading.to_owned()
    let value = Value(6)
    assert(reading(value) == 6, "original reading function")
    assert(reading_copy(value) == 6, "clone retains borrowed parameter access")
    assert(reading_owned(value) == 6, "owned reading function")
    assert(value.number == 6, "reading callbacks preserve their argument")
    let zero = duplicate(answer)
    assert(zero() == 42, "zero-argument function clone")
    let update = duplicate(increment)
    var number = 4
    assert(update(mut number, 3) == 7 && number == 7,
        "multi-argument clone preserves exclusive parameter access")
    let regional: for<region r> fn(read i32 from r): read i32 from r = identity
    let regional_copy = duplicate(regional)
    assert(*regional_copy(number) == 7, "higher-ranked result regions survive cloning")
    let fallible = duplicate(may_fail)
    match take capture fallible(true) {
        failure(Failure.Rejected) => {},
        _ => { return 1 }
    }
    match take capture fallible(false) {
        success(result) => { assert(result == 9, "throwing function success") },
        _ => { return 2 }
    }
    let restricted: unsafe fn(): i32 = answer
    let restricted_copy = duplicate(restricted)
    assert(unsafe { restricted_copy() } == 42, "unsafe function type survives cloning")
    let foreign: extern "C" fn(i32): i32 = foreign_increment
    let foreign_copy = duplicate(foreign)
    assert(foreign_copy(8) == 9, "foreign calling convention survives cloning")
    0
}
