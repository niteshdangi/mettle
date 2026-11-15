// profiles: debug release
import core.convert.{From, Into, TryFrom}
import core.default.Default
import core.iter.OwnedIterable
import core.fmt.{buffer_writer, formatter, spec}

type Converted { value: i32 }
extend Converted implements From<i32> {
    static fn from(take value: i32): Converted { Converted(value) }
}
fn fallback<T, U: Into<T>>(take value: U): Outcome<T, Never> {
    T.(TryFrom<U>).try_from(value)
}
fn default_pointer<T: unsized + Thin>(): ptr<mut T> { ptr<mut T>.(Default).default() }
fn frozen<T: Freeze>(take value: T): T { value }
fn unpin<T: unsized + Unpin>(): Unit {}
fn function_traits<F: core.ops.FnPtr + core.fmt.Debug + core.fmt.Pointer + core.hash.Hash + core.cmp.Ord>(read value: F): bool {
    if F.(core.cmp.Ord).cmp(value, value) != core.cmp.Ordering.Equal { return false }
    if core.hash.hash_one(value) != core.hash.hash_one(core.intrinsics.fn_addr(value)) { return false }
    var bytes = [0u8; 64]
    var writer = buffer_writer(mut bytes)
    var f = formatter(mut writer, spec())
    match capture F.(core.fmt.Pointer).fmt(value, mut f) {
        success(_) => {},
        failure(_) => { return false }
    }
    match capture F.(core.fmt.Debug).fmt(value, mut f) {
        success(_) => {},
        failure(_) => { return false }
    }
    true
}
fn increment(value: i32): i32 { value + 1 }

fn main(): i32 {
    match fallback<Converted, i32>(7i32) {
        success(value) => if value.value != 7i32 { return 1 }
    }
    match fallback<i32, i16>(9i16) {
        success(value) => if value != 9i32 { return 1 }
    }
    if !default_pointer<i32>().is_null() || !ptr<read i32>.(Default).default().is_null() { return 5 }
    let function: fn(i32): i32 = increment
    if !function_traits(function) { return 2 }
    if core.intrinsics.fn_addr(function) == 0usize { return 2 }
    if frozen(function)(4i32) != 5i32 { return 3 }
    unpin<[i32]>()
    var optional = present(9i32).into_iter()
    if optional.next() != present(9i32) || optional.next().is_present() { return 4 }
    0
}
