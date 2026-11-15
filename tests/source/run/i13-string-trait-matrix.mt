// profiles: debug release
// Every standard-trait implementation of String and its drain, called through the
// trait so each implementation is resolved on its own: comparison, conversion,
// extension, hashing, operators, indexing and formatting.
import alloc.borrow.BorrowedOrOwned
import alloc.boxed.Heap
import alloc.ffi.CString
import alloc.string.{String, ToString}
import alloc.vec
import core.borrow.{AsRef, Borrow}
import core.clone.Clone
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.convert.{From, TryFrom}
import core.fmt
import core.fmt.{Debug, Write}
import core.hash.hash_one
import core.iter.{BidirectionalIterator, ExtendItems, FromItems, Iterator}
import core.ops.{Add, AddAssign, Deref, DerefMut}
import std.ffi.OsStr
import std.path.{Path, PathBuf, path_buf_from_text}

fn require_eq<T: Eq>(read value: T): Unit {}
fn debug_text<T: Debug>(read value: T): String {
    var output = String("")
    var formatter = fmt.formatter(mut output, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => {}
    }
    output
}
fn copy_string<region r>(take value: read String from r): String {
    String.(From<read String from r>).from(value)
}
fn text_view_is<T: AsRef<Text>>(read value: T, read expected: Text): bool {
    T.(AsRef<Text>).as_ref(value) == expected
}
fn byte_view_len<T: AsRef<[u8]>>(read value: T): usize {
    T.(AsRef<[u8]>).as_ref(value).len()
}

fn checks_comparison(): i32 {
    let apple = String("apple")
    let banana = String("banana")
    let again = String.(Clone).clone(apple)
    if !String.(PartialEq).eq(again, apple) || String.(PartialEq).eq(apple, banana) { return 1 }
    require_eq(read apple)
    if String.(Ord).cmp(apple, banana) != Ordering.Less { return 2 }
    if String.(Ord).cmp(banana, apple) != Ordering.Greater || String.(Ord).cmp(apple, again) != Ordering.Equal { return 3 }
    if String.(PartialOrd).partial_cmp(apple, banana) != present(Ordering.Less) { return 4 }
    if String.(PartialEq<Text>).eq(apple, "apple") == false || String.(PartialEq<Text>).eq(apple, "pear") { return 5 }
    if !String.(PartialEq<read Text from static>).eq(apple, "apple") { return 9 }
    if !Text.(PartialEq<String>).eq("apple", apple) { return 20 }
    let text_view: read Text from static = "apple"
    if !(text_view == apple) { return 21 }
    let view: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Owned(String("apple"))
    if !String.(PartialEq<BorrowedOrOwned<region static, Text>>).eq(apple, view) { return 6 }
    let borrowed_view: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("apple")
    if !Text.(PartialEq<BorrowedOrOwned<region static, Text>>).eq("apple", borrowed_view) { return 18 }
    if !(text_view == borrowed_view) { return 22 }
    if !BorrowedOrOwned<region static, Text>.(PartialEq<String>).eq(borrowed_view, apple) { return 19 }
    let path = path_buf_from_text("apple")
    if !String.(PartialEq<PathBuf>).eq(apple, path) || String.(PartialEq<Path>).eq(banana, path.as_path()) { return 7 }
    if hash_one(apple) != hash_one(again) || hash_one(apple) == hash_one(banana) { return 8 }
    0
}

fn checks_views_and_conversions(): i32 {
    let source = String("data")
    if String.(AsRef<Text>).as_ref(source).len() != 4usize { return 10 }
    if String.(AsRef<[u8]>).as_ref(source).len() != 4usize { return 11 }
    if String.(AsRef<OsStr>).as_ref(source).as_bytes() != "data".as_bytes() { return 12 }
    if String.(AsRef<Path>).as_ref(source).as_os_str().as_bytes() != "data".as_bytes() { return 13 }
    if String.(Borrow<Text>).borrow(source) != "data" { return 14 }
    if String.(Deref).deref(source) != "data" { return 15 }
    var mutable = String("ab")
    String.(DerefMut).deref_mut(mut mutable).make_ascii_uppercase()
    if mutable.as_text() != "AB" { return 16 }

    var exclusive = String("xy")
    let owned_from_mut = String.(From<mut Text>).from(exclusive.as_mut_str())
    if owned_from_mut.as_text() != "xy" { return 17 }
    let copied = copy_string(read source)
    if copied.as_text() != "data" { return 18 }
    let borrowed: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("borrowed")
    if String.(From<BorrowedOrOwned<region static, Text>>).from(borrowed).as_text() != "borrowed" { return 19 }
    let c_string = match take capture CString.new(vec.from_array([104u8, 105u8])) {
        success(value) => value,
        failure(_) => { return 20 }
    }
    match take String.(TryFrom<CString>).try_from(take c_string) {
        success(text) => { if text.as_text() != "hi" { return 21 } },
        failure(_) => { return 22 }
    }
    if source.to_string().as_text() != "data" { return 23 }
    0
}

fn checks_building(): i32 {
    var text = String("a")
    text = String.(Add<read Text from static>).add(text, "b")
    String.(AddAssign<read Text from static>).add_assign(mut text, "c")
    if text.as_text() != "abc" { return 30 }

    let cow_left: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("x")
    let cow_right: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("y")
    let cow_joined = BorrowedOrOwned<region static, Text>.(
        Add<BorrowedOrOwned<region static, Text>>
    ).add(cow_left, cow_right)
    if !cow_joined.is_owned() || cow_joined.as_ref() != "xy" { return 35 }

    let cow_prefix: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("a")
    let cow_with_text = BorrowedOrOwned<region static, Text>.(
        Add<read Text from static>
    ).add(cow_prefix, "b")
    if !cow_with_text.is_owned() || cow_with_text.as_ref() != "ab" { return 36 }

    var cow_assign: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("c")
    let cow_suffix: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("d")
    BorrowedOrOwned<region static, Text>.(
        AddAssign<BorrowedOrOwned<region static, Text>>
    ).add_assign(mut cow_assign, cow_suffix)
    if !cow_assign.is_owned() || cow_assign.as_ref() != "cd" { return 37 }

    var cow_assign_text: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("e")
    BorrowedOrOwned<region static, Text>.(
        AddAssign<read Text from static>
    ).add_assign(mut cow_assign_text, "f")
    if !cow_assign_text.is_owned() || cow_assign_text.as_ref() != "ef" { return 38 }

    var sink = String("")
    match take capture String.(Write).write_str(mut sink, "w") {
        success(_) => {},
        failure(_) => { return 31 }
    }
    if sink.as_text() != "w" { return 31 }

    var pieces = vec.new<BorrowedOrOwned<region static, Text>>()
    pieces.push(BorrowedOrOwned.Borrowed("x"))
    pieces.push(BorrowedOrOwned.Owned(String("y")))
    let joined = String.(FromItems<BorrowedOrOwned<region static, Text>>).from_iter(take pieces)
    if joined.as_text() != "xy" { return 32 }
    var strings = vec.new<String>()
    strings.push(String("p"))
    strings.push(String("q"))
    let collected = String.(FromItems<String>).from_iter(take strings)
    if collected.as_text() != "pq" { return 33 }

    var extended = String(">")
    var owned_pieces = vec.new<BorrowedOrOwned<region static, Text>>()
    owned_pieces.push(BorrowedOrOwned.Owned(String("1")))
    String.(ExtendItems<BorrowedOrOwned<region static, Text>>).extend(mut extended, take owned_pieces)
    var texts = vec.new<read Text from static>()
    texts.push("2")
    String.(ExtendItems<read Text from static>).extend(mut extended, take texts)
    var boxes = vec.new<Heap<Text>>()
    boxes.push(Heap<Text>.(From<read Text from static>).from("3"))
    String.(ExtendItems<Heap<Text>>).extend(mut extended, take boxes)
    var more = vec.new<String>()
    more.push(String("4"))
    String.(ExtendItems<String>).extend(mut extended, take more)
    if extended.as_text() != ">1234" { return 34 }
    0
}

fn checks_indexing_and_drain(): i32 {
    var text = String("hello world")
    if read text[0usize..5usize] != "hello" { return 40 }
    {
        let head = mut text[0usize..1usize]
        head.make_ascii_uppercase()
    }
    if text.as_text() != "Hello world" { return 41 }

    let observed = {
        var drained = text.drain(0usize, 5usize)
        if !text_view_is(drained, "Hello") { return 42 }
        if byte_view_len(drained) != 5usize { return 43 }
        if !debug_text(drained).as_text().starts_with("Drain") { return 48 }
        match drained.next() { present(c) => { if c != 'H' { return 44 } }, none => { return 44 } }
        match drained.next_back() { present(c) => { if c != 'o' { return 45 } }, none => { return 45 } }
        if drained.as_str() != "ell" { return 46 }
        1
    }
    if observed != 1 || text.as_text() != " world" { return 47 }
    0
}

fn main(): i32 {
    let first = checks_comparison()
    if first != 0 { return first }
    let second = checks_views_and_conversions()
    if second != 0 { return second }
    let third = checks_building()
    if third != 0 { return third }
    checks_indexing_and_drain()
}
