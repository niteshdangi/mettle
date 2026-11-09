// profiles: debug release

import alloc.rc
import alloc.vec.List
import core.borrow.Borrow
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.convert.{From, TryFrom}
import core.default.Default
import core.fmt
import core.fmt.{Debug, Display}
import core.hash.{Hash, Hasher, fnv1a}
import core.iter.FromItems
import core.ops.Deref
import core.text.Text
import core.any.Any

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read buffer, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn display_is<T: Display>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Display).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read buffer, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn hash_matches<T: Hash>(read value: T, read expected: i32): bool {
    var actual = fnv1a()
    value.hash(mut actual)
    var baseline = fnv1a()
    expected.hash(mut baseline)
    actual.finish() == baseline.finish()
}

fn main(): i32 {
    let one = rc.Rc<i32>.(From<i32>).from(1)
    let two = rc.Rc<i32>.(From<i32>).from(2)
    if one == two || !(one < two) { return 1 }
    match one.cmp(two) {
        Ordering.Less => {},
        _ => { return 2 }
    }
    let _eq: bool = one.eq(two)
    let _partial: core.cmp.Ordering? = one.partial_cmp(two)
    let dereferenced: read i32 = one.deref()
    if *dereferenced != 1 { return 3 }
    let borrowed: read i32 = rc.Rc<i32>.(Borrow<i32>).borrow(one)
    if *borrowed != 1 { return 4 }
    if !debug_is(one, "1") || !display_is(one, "1") { return 5 }
    if !hash_matches(one, 1) { return 6 }

    let values = List<i32>.(From<[i32; 2]>).from([3, 4])
    let slice = rc.Rc<[i32]>.(FromItems<i32>).from_iter(values.into_iter())
    if slice.get().len() != 2usize || slice.get()[1usize] != 4 { return 7 }

    let array_slice = rc.Rc<[i32]>.(From<[i32; 3]>).from([5, 6, 7])
    if array_slice.get().len() != 3usize || array_slice.get()[2usize] != 7 {
        return 10
    }
    match take rc.Rc<[i32; 3]>.(TryFrom<rc.Rc<[i32]>>).try_from(array_slice) {
        success(array) => {
            if array.get()[0usize] != 5 || array.get()[2usize] != 7 { return 11 }
        },
        failure(_) => { return 12 }
    }
    let wrong_length = rc.Rc<[i32]>.(From<[i32; 2]>).from([8, 9])
    match take rc.Rc<[i32; 3]>.(TryFrom<rc.Rc<[i32]>>).try_from(wrong_length) {
        success(_) => { return 13 },
        failure(original) => {
            if original.get().len() != 2usize || original.get()[1usize] != 9 {
                return 14
            }
        }
    }

    let erased: rc.Rc<any Any> = rc.new(25i32)
    match take erased.downcast<i32>() {
        success(value) => { if *value.get() != 25 { return 15 } },
        failure(_) => { return 16 }
    }
    let erased_wrong: rc.Rc<any Any> = rc.new(26i32)
    match take erased_wrong.downcast<u32>() {
        success(_) => { return 17 },
        failure(value) => {
            match take value.downcast<i32>() {
                success(original) => { if *original.get() != 26 { return 18 } },
                failure(_) => { return 19 }
            }
        }
    }

    let owner = rc.new(6)
    let `weak` = owner.downgrade()
    if !debug_is(`weak`, "(Weak)") { return 8 }
    if rc.Weak<i32>.(Default).default().strong_count() != 0usize {
        return 9
    }
    0
}
