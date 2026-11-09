// profiles: debug release
import core.cmp.{PartialEq, Eq, PartialOrd, Ord, Ordering}
import core.default.Default
import core.hash.{Hash, Hasher, fnv1a}
import core.borrow.{AsRef, AsMut}
import core.ops.{Index, IndexMut}
import core.fmt
import core.fmt.{Debug, Display, Spec}
import core.text.Text

fn debug_is<T: Debug + unsized>(read value: T, read expected: Text): bool {
    var storage = [0u8; 200]
    var writer = fmt.buffer_writer(mut storage)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read storage, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn display_is<T: Display + unsized>(read value: T, read expected: Text): bool {
    var storage = [0u8; 200]
    var writer = fmt.buffer_writer(mut storage)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Display).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read storage, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn digest<T: Hash + unsized>(read value: T): u64 {
    var h = fnv1a()
    value.hash(mut h)
    h.finish()
}

fn is_eq<T: Eq + unsized>(read a: T, read b: T): bool { a == b }
fn order<T: Ord + unsized>(read a: T, read b: T): Ordering { a.cmp(read b) }
fn partial<T: PartialOrd + unsized>(read a: T, read b: T): Ordering? { a.partial_cmp(read b) }
fn make<T: Default>(): T { T.(Default).default() }
fn view_len<T: AsRef<[i32]>>(read value: T): usize { value.as_ref().len() }
fn set_first<T: AsMut<[i32]>>(mut value: T) {
    let slots: mut [i32] = value.as_mut()
    slots[0usize] = 9
}

fn main(): i32 {
    let arr = [1i32, 2i32, 3i32]
    let view: read [i32] = read arr
    let text = "ab"
    let units = ()
    let pair = (1i32, true)

    if !debug_is(read arr, "[1, 2, 3]") || !debug_is(view, "[1, 2, 3]") { return 1 }
    if !debug_is(text, "\"ab\"") || !debug_is(pair, "(1, true)") { return 2 }
    if !debug_is(units, "()") { return 3 }
    if !display_is(text, "ab") { return 4 }

    if !is_eq(read arr, read [1i32, 2i32, 3i32]) || !is_eq(view, view) { return 5 }
    if !is_eq(text, "ab") || !is_eq(pair, read (1i32, true)) || !is_eq(units, read ()) { return 6 }

    if order(read arr, read [1i32, 2i32, 4i32]) != Ordering.Less { return 7 }
    if order(view, view) != Ordering.Equal { return 8 }
    if order(text, "b") != Ordering.Less || order("ab", "aa") != Ordering.Greater { return 9 }
    if order(pair, read (1i32, false)) != Ordering.Greater || order(units, read ()) != Ordering.Equal { return 10 }
    match partial(text, "ab") { present(o) => { if o != Ordering.Equal { return 11 } }, none => { return 11 } }

    if digest(read arr) != digest(view) || digest(text) == digest("ac") { return 12 }
    if digest(units) != digest(read ()) { return 13 }

    let d: [i32; 3] = make()
    if d[2usize] != 0 { return 14 }

    if view_len(read arr) != 3usize { return 15 }
    var mutable = [5i32, 6i32]
    set_first(mut mutable)
    if mutable[0usize] != 9 { return 16 }

    if *arr.index(read 1usize) != 2 || *view.index(read 2usize) != 3 { return 17 }
    let empty_text: read Text = make()
    let unit_value: Unit = make()
    if empty_text.len() != 0usize || unit_value != () { return 19 }
    var total = 0
    for x in arr.iter() { total += *x }
    for x in view.iter() { total += *x }
    if total != 12 { return 20 }
    var bump = [1i32, 1i32]
    for x in bump.iter_mut() { *x += 1 }
    if bump[1usize] != 2 { return 21 }
    var idx = [7i32, 8i32]
    *idx.index_mut(read 0usize) = 4
    if idx[0usize] != 4 { return 18 }
    0
}
