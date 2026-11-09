// profiles: debug release
import alloc.boxed
import alloc.boxed.Box
import alloc.borrow.Cow
import alloc.string
import alloc.vec.{List, IntoIter}
import core.borrow.{AsMut, AsRef, Borrow, BorrowMut}
import core.clone.Clone
import core.cmp.{Ord, Ordering}
import core.convert.From
import core.default.Default
import core.error.Error
import core.fmt
import core.fmt.{Debug, Display}
import core.hash.{Hash, Hasher, fnv1a}
import core.future.{Context, Future, Poll, noop_waker}
import core.iter.{FromItems, Iterator, OwnedIterable}
import core.ops.{Deref, DerefMut}
import core.text.Text

type Oops {
    code: i32
}
extend Oops implements Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try f.write_str("oops") }
}
extend Oops implements Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try f.write_str("oops") }
}
extend Oops implements Error {}

fn assert_error<E: Error>(value: read E): bool { true }

fn as_view<V: AsRef<[i32]>>(value: read V): read [i32] from value { V.(AsRef<[i32]>).as_ref(value) }

fn from_cow<region r>(value: take Cow<region r, i32>): Box<[i32]> {
    Box<[i32]>.(From<Cow<region r, i32>>).from(value)
}

fn debug_is<T: Debug>(value: read T, expected: read Text): bool {
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

fn display_is<T: Display>(value: read T, expected: read Text): bool {
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
    let single = Box<i32>.(From<i32>).from(5)
    if *single.get() != 5 { return 1 }
    if *Box<i32>.(Borrow<i32>).borrow(read single) != 5 { return 2 }
    if !debug_is(read single, "5") || !display_is(read single, "5") { return 3 }

    var mutable = boxed.new(4)
    *Box<i32>.(BorrowMut<i32>).borrow_mut(mut mutable) = 6
    if *mutable.get() != 6 { return 4 }
    *Box<i32>.(AsMut<i32>).as_mut(mut mutable) = 7
    if *mutable.get() != 7 { return 5 }
    *Box<i32>.(DerefMut).deref_mut(mut mutable) = 8
    if *Box<i32>.(Deref).deref(read mutable) != 8 { return 6 }

    let other = boxed.new(8)
    if mutable != other || !(boxed.new(1) < other) { return 7 }
    match boxed.new(2).cmp(read other) {
        Ordering.Less => {},
        _ => { return 8 }
    }
    var hasher_a = fnv1a()
    other.hash(mut hasher_a)
    var hasher_b = fnv1a()
    8.hash(mut hasher_b)
    if hasher_a.finish() != hasher_b.finish() { return 9 }

    var hasher_box = boxed.new(fnv1a())
    if hasher_box.finish() != fnv1a().finish() { return 10 }

    let copied = boxed.new(12).clone()
    if *copied.get() != 12 { return 11 }

    let source = [1, 2, 3]
    let source_view: read [i32] = read source
    let from_ref = Box<[i32]>.(From<read [i32]>).from(source_view)
    if from_ref.get().len() != 3usize || from_ref.get()[2usize] != 3 { return 12 }
    let arr_box = Box<[i32]>.(From<[i32; 2]>).from([4, 5])
    if arr_box.get()[1usize] != 5 { return 13 }
    var mutable_source = [8, 9]
    let mut_view: mut [i32] = mut mutable_source
    let mut_box = Box<[i32]>.(From<mut [i32]>).from(take mut_view)
    if mut_box.get()[0usize] != 8 { return 15 }
    let list_box = Box<[i32]>.(From<List<i32>>).from(List<i32>.(From<[i32; 2]>).from([10, 11]))
    if list_box.get()[1usize] != 11 { return 16 }
    let cow_box = from_cow(Cow.Owned(List<i32>.(From<[i32; 1]>).from([12])))
    if cow_box.get()[0usize] != 12 { return 17 }

    let text_box = Box<Text>.(From<read Text>).from("hi")
    if text_box.get() != "hi" { return 18 }
    let owned_text = Box<Text>.(From<string.String>).from(string.from_text("abc"))
    if owned_text.get() != "abc" { return 19 }

    let char_list = List<char>.(From<[char; 2]>).from(['x', 'y'])
    let chars = List<char>.(FromItems<char>).from_iter(char_list.into_iter())
    let from_chars = Box<Text>.(FromItems<char>).from_iter(chars.into_iter())
    if from_chars.get() != "xy" { return 20 }

    let items = Box<[i32]>.(FromItems<i32>).from_iter(List<i32>.(From<[i32; 2]>).from([13, 14]).into_iter())
    if items.get()[0usize] != 13 { return 21 }

    var total = 0
    for x in items { total += *x }
    if total != 27 { return 22 }
    let view_total = as_view(read items)
    if view_total[1usize] != 14 { return 23 }

    let err: Box<Oops> = boxed.new(Oops(3))
    if !assert_error(read err) { return 24 }

    let raw = boxed.new(9)
    let nn = raw.into_non_null()
    let back = unsafe { boxed.from_non_null(nn) }
    if *back.get() != 9 { return 25 }

    let pinned_box = boxed.new(3).into_pinned()
    if *pinned_box.get_ref() != 3 { return 28 }

    let adder = boxed.new(fn(x: i32): i32 { x + 1 })
    if adder.get()(3) != 4 { return 26 }

    var counter = boxed.new(List<i32>.(From<[i32; 2]>).from([15, 16]).into_iter())
    if counter.next().unwrap() != 15 { return 27 }
    let pending = boxed.new(AddOne(41))
    if drive(pending) != 42 { return 29 }
    0
}



fn drive<F: Future>(future: take F): F.Output {
    let waker = noop_waker()
    var slot = core.pin.pin(future)
    loop {
        var cx = Context.from_waker(read waker)
        match take slot.as_mut().poll(mut cx) {
            Poll.Ready(value) => { return value },
            Poll.Pending => {}
        }
    }
}

type AddOne {
    value: i32
}
unsafe extend AddOne implements Unpin {}
extend AddOne implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> { Poll.Ready(unsafe { self.get_unchecked_mut() }.value + 1) }
}
