// profiles: debug release
module source_helpers;
import alloc.boxed
import alloc.boxed.Heap
import alloc.borrow.BorrowedOrOwned
import alloc.string
import alloc.vec.{List, IntoIter}
import core.borrow.{AsMut, AsRef, Borrow, BorrowMut}
import core.any.Any
import core.clone.Clone
import core.cmp.{Eq, Ord, Ordering}
import core.convert.{From, TryFrom}
import core.default.Default
import core.error.Error
import core.fmt
import core.fmt.{Debug, Display}
import core.hash.{Hash, Hasher, fnv1a}
import core.future.{Context, Future, Poll}
import core.iter.{FromItems, Iterator, OwnedIterable}
import core.ops.{Deref, DerefMut}
import core.text.Text

type Oops {
    code: i32
}
extend Oops implements Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("oops") }
}
extend Oops implements Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error { try f.write_str("oops") }
}
extend Oops implements Error {}

fn assert_error<E: Error>(read value: E): bool { true }
fn equal<T: Eq>(read left: T, read right: T): bool { left == right }

fn as_view<V: AsRef<[i32]>>(read value: V): read [i32] from value { V.(AsRef<[i32]>).as_ref(value) }

fn from_cow<region r>(take value: BorrowedOrOwned<region r, [i32]>): Heap<[i32]> {
    Heap<[i32]>.(From<BorrowedOrOwned<region r, [i32]>>).from(value)
}

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn display_is<T: unsized + Display>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Display).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn main(): i32 {
    let single = Heap<i32>.(From<i32>).from(5)
    if *single.get() != 5 { return 1 }
    if *Heap<i32>.(Borrow<i32>).borrow(read single) != 5 { return 2 }
    if !debug_is(read single, "5") || !display_is(read single, "5") { return 3 }

    var mutable = boxed.new(4)
    *Heap<i32>.(BorrowMut<i32>).borrow_mut(mut mutable) = 6
    if *mutable.get() != 6 { return 4 }
    *Heap<i32>.(AsMut<i32>).as_mut(mut mutable) = 7
    if *mutable.get() != 7 { return 5 }
    *Heap<i32>.(DerefMut).deref_mut(mut mutable) = 8
    if *Heap<i32>.(Deref).deref(read mutable) != 8 { return 6 }

    let other = boxed.new(8)
    if mutable != other || !(boxed.new(1) < other) { return 7 }
    if !equal(read mutable, read other) ||
        equal(read mutable, read boxed.new(9)) ||
        *mutable.get() != 8 {
        return 65
    }
    match boxed.new(2).cmp(read other) {
        Ordering.Less => {},
        _ => { return 8 }
    }
    var hasher_a = fnv1a()
    other.hash(mut hasher_a)
    var hasher_b = fnv1a()
    8.hash(mut hasher_b)
    if hasher_a.finish() != hasher_b.finish() { return 9 }

    let copied = boxed.new(12).clone()
    if *copied.get() != 12 { return 11 }

    let source = [1, 2, 3]
    let source_view: read [i32] = read source
    let from_ref = Heap<[i32]>.(From<read [i32]>).from(source_view)
    if from_ref.get().len() != 3usize || from_ref.get()[2usize] != 3 { return 12 }
    let arr_box = Heap<[i32]>.(From<[i32; 2]>).from([4, 5])
    if arr_box.get()[1usize] != 5 { return 13 }
    var mutable_source = [8, 9]
    let mut_view: mut [i32] = mut mutable_source
    let mut_box = Heap<[i32]>.(From<mut [i32]>).from(take mut_view)
    if mut_box.get()[0usize] != 8 { return 15 }
    let list_box = Heap<[i32]>.(From<List<i32>>).from(List<i32>.(From<[i32; 2]>).from([10, 11]))
    if list_box.get()[1usize] != 11 { return 16 }
    let cow_box = from_cow(BorrowedOrOwned.Owned(List<i32>.(From<[i32; 1]>).from([12])))
    if cow_box.get()[0usize] != 12 { return 17 }
    let borrowed_items: read [i32] = read [13, 14]
    let cow_box_borrowed = from_cow(BorrowedOrOwned.Borrowed(borrowed_items))
    if cow_box_borrowed.get()[1usize] != 14 { return 61 }

    let text_box = Heap<Text>.(From<read Text>).from("hi")
    if text_box.get() != "hi" { return 18 }
    let equivalent_text = boxed.copy_text("hi")
    if !equal(read text_box, read equivalent_text) ||
        text_box.get() != "hi" {
        return 66
    }
    var mutable_text_source = boxed.copy_text("mutable")
    let mutable_text_view: mut Text = mutable_text_source.get_mut()
    let copied_mutable_text = Heap<Text>.(From<mut Text>).from(take mutable_text_view)
    if copied_mutable_text.get() != "mutable" { return 64 }
    let owned_text = Heap<Text>.(From<string.String>).from(string.from_text("abc"))
    if owned_text.get() != "abc" { return 19 }
    let text_bytes = Heap<[u8]>.(From<Heap<Text>>).from(
        Heap<Text>.(From<read Text>).from("abc")
    )
    if text_bytes.get().len() != 3usize || text_bytes.get()[2usize] != 99u8 {
        return 54
    }

    let char_list = List<char>.(From<[char; 2]>).from(['x', 'y'])
    let chars = List<char>.(FromItems<char>).from_iter(char_list.into_iter())
    let from_chars = Heap<Text>.(FromItems<char>).from_iter(chars.into_iter())
    if from_chars.get() != "xy" { return 20 }

    let items = Heap<[i32]>.(FromItems<i32>).from_iter(List<i32>.(From<[i32; 2]>).from([13, 14]).into_iter())
    if items.get()[0usize] != 13 { return 21 }

    var total = 0
    for x in items { total += *x }
    if total != 27 { return 22 }
    let view_total = as_view(read items)
    if view_total[1usize] != 14 { return 23 }

    let err: Heap<Oops> = boxed.new(Oops(3))
    if !assert_error(read err) { return 24 }
    let erased_error: Heap<any Error> = Heap<any Error>.(From<Oops>).from(Oops(4))
    if !display_is(read erased_error, "oops") { return 58 }
    let text_error: Heap<any Error> =
        Heap<any Error>.(From<read Text>).from("text error")
    if !display_is(read text_error, "text error") { return 59 }
    let string_error: Heap<any Error> =
        Heap<any Error>.(From<string.String>).from(string.from_text("string error"))
    if !display_is(read string_error, "string error") { return 60 }

    let raw = boxed.new(9)
    let nn = raw.into_non_null()
    let back = unsafe { boxed.from_non_null(nn) }
    if *back.get() != 9 { return 25 }

    let pinned_box = boxed.new(3).into_pinned()
    if *pinned_box.get_ref() != 3 { return 28 }

    let adder = boxed.new(fn(x: i32): i32 { x + 1 })
    if adder.get()(3) != 4 { return 26 }
    if adder(3) != 4 { return 30 }
    var captured = 20
    var boxed_mutable = boxed.new(fn(extra: i32): i32 { captured += extra; captured })
    if boxed_mutable(22) != 42 { return 50 }

    let array_box = match take Heap<[i32; 2]>.(TryFrom<Heap<[i32]>>).try_from(
        Heap<[i32]>.(From<[i32; 2]>).from([20, 21])
    ) {
        success(value) => value,
        failure(_) => { return 31 }
    }
    if array_box.get()[1usize] != 21 { return 32 }
    let list_array = match take Heap<[i32; 2]>.(TryFrom<List<i32>>).try_from(
        List<i32>.(From<[i32; 2]>).from([22, 23])
    ) {
        success(value) => value,
        failure(_) => { return 33 }
    }
    if list_array.get()[0usize] != 22 { return 34 }
    match Heap<[i32; 2]>.(TryFrom<Heap<[i32]>>).try_from(
        Heap<[i32]>.(From<[i32; 1]>).from([24])
    ) {
        success(_) => { return 35 },
        failure(original) => {
            if original.get().len() != 1usize || original.get()[0usize] != 24 {
                return 36
            }
        }
    }
    match Heap<[i32; 2]>.(TryFrom<List<i32>>).try_from(
        List<i32>.(From<[i32; 1]>).from([29])
    ) {
        success(_) => { return 62 },
        failure(original) => {
            if original.len() != 1usize || original[0usize] != 29 { return 63 }
        }
    }
    let erased: Heap<any Any> = boxed.new(25)
    match take erased.downcast<i32>() {
        success(value) => { if *value.get() != 25 { return 37 } },
        failure(_) => { return 38 }
    }
    let erased_wrong: Heap<any Any> = boxed.new(26)
    match take erased_wrong.downcast<u32>() {
        success(_) => { return 39 },
        failure(original) => {
            if !core.any.is<i32>(original.get()) { return 40 }
        }
    }
    var counter = boxed.new(List<i32>.(From<[i32; 2]>).from([15, 16]).into_iter())
    if counter.next().or_panic() != 15 { return 27 }
    let pending = boxed.new(AddOne(41))
    if drive(pending) != 42 { return 29 }
    0
}



fn drive<F: Future>(take future: F): F.Output {
    source_helpers.drive!(future)
}

type AddOne {
    value: i32
}
unsafe extend AddOne implements Unpin {}
extend AddOne implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> { Poll.Ready(unsafe { self.get_unchecked_mut() }.value + 1) }
}
