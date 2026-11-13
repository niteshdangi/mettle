// profiles: debug release
module source_helpers;
import core.borrow.{AsRef, Borrow, ToOwned}
import core.cmp.{Ord, Ordering, PartialEq, PartialOrd}
import core.convert.From
import core.default.Default
import core.fmt.{Debug, Write}
import core.iter.{ExtendItems, FromItems}
import core.iter.{RangeFull, range_full}
import core.ops.{Deref, DerefMut, Index, IndexMut}
import core.text.Text
import core.text.FromStr
import alloc.string.String
import alloc.vec.List
import std.ffi.{OsStr, OsString, os_string_from_text}

fn default_value<T: Default>(): T { T.(Default).default() }
fn copy_os<region r, T: unsized>(take value: read T from r): OsString
where OsString: From<read T from r> {
    OsString.(From<read T from r>).from(value)
}
fn debug_is<T: Debug + unsized>(read value: T, read expected: Text): bool {
    source_helpers.debug_is!(T, value, expected)
}
fn ord_equal<T: Ord + Copy>(left: T, right: T): bool { left.cmp(right).is_eq() }
fn view_eq<A: PartialEq<B> + Copy, B: Copy>(left: A, right: B): bool { left.eq(right) }
fn owned_partial<A: PartialOrd<B>, B: Copy>(read left: A, right: B): bool {
    left.partial_cmp(right) == present(Ordering.Equal)
}
fn view_partial<A: PartialOrd<B> + Copy, B>(left: A, read right: B): bool {
    left.partial_cmp(right) == present(Ordering.Equal)
}

fn main(): i32 {
    let view = OsStr.new("alpha".as_bytes())
    if !debug_is(view, "\"alpha\"") { return 24 }
    let owned = view.to_owned()
    if !debug_is(owned, "\"alpha\"") { return 25 }
    let self_reference: read OsStr = OsStr.(AsRef<OsStr>).as_ref(view)
    if !view_eq(self_reference, view) || !view_eq(view, "alpha") ||
        !OsString.(PartialOrd<read Text>).partial_cmp(owned, "alpha").unwrap().is_eq() {
        return 30
    }
    if !view.same(owned.as_os_str()) { return 1 }
    if !view.same(OsStr.new("alpha".as_bytes())) { return 21 }
    if !(owned >= view) { return 22 }
    if !ord_equal(view, view) { return 17 }
    if !owned_partial(owned, view) { return 19 }
    if !view_partial(view, owned) { return 20 }
    if !owned.cmp(os_string_from_text("alpha")).is_eq() { return 2 }
    let from_text = OsString.(From<read Text from static>).from("alpha")
    let string_input = alloc.string.from_text("alpha")
    let from_string_view = copy_os(read string_input)
    let from_string = OsString.(From<String>).from(string_input)
    let from_view = OsString.(From<read OsStr from static>).from(OsStr.new("alpha".as_bytes()))
    let from_osstring_view = copy_os(read owned)
    if !from_text.eq(owned) || !from_string.eq(owned) || !from_view.eq(owned) ||
        !from_string_view.eq(owned) || !from_osstring_view.eq(owned) { return 23 }

    let borrowed = OsString.(Borrow<OsStr>).borrow(owned)
    let referenced = OsString.(AsRef<OsStr>).as_ref(owned)
    if !view_eq(borrowed, referenced) || !view_eq(borrowed, view) { return 3 }
    if !view_eq(OsString.(Deref).deref(owned), view) { return 15 }
    if core.hash.hash_one(owned) != core.hash.hash_one(view) { return 4 }

    let default = OsString.default()
    if !default.is_empty() { return 5 }
    match capture OsString.(FromStr).from_str("parsed") {
        success(parsed) => { if parsed.as_bytes()[0usize] != 112u8 { return 6 } }
    }

    let items: [OsString; 2] = [
        os_string_from_text("one"),
        os_string_from_text("two")
    ]
    let collected = OsString.(FromItems<OsString>).from_iter(List<OsString>.(From<[OsString; 2]>).from(items))
    if !collected.eq(os_string_from_text("onetwo")) { return 7 }
    var appended = OsString.new()
    OsString.(ExtendItems<OsString>).extend(mut appended, List<OsString>.(From<[OsString; 2]>).from([
        os_string_from_text("first"),
        os_string_from_text("second")
    ]))
    if !appended.eq(os_string_from_text("firstsecond")) { return 8 }
    {
        let full_mut = OsString.(IndexMut<RangeFull>).index_mut(mut appended, range_full())
        full_mut.make_ascii_uppercase()
    }
    if !appended.eq(os_string_from_text("FIRSTSECOND")) { return 9 }
    let full_view = OsString.(Index<RangeFull>).index(appended, range_full())
    if full_view.as_bytes().len() != 11usize { return 10 }
    var bytes_mut = OsString.(DerefMut).deref_mut(mut appended)
    bytes_mut.make_ascii_lowercase()
    if !appended.eq(os_string_from_text("firstsecond")) { return 11 }
    let leaked = os_string_from_text("leaked").leak()
    if !leaked.to_str().is_present() { return 16 }

    var writer = OsString.new()
    match capture writer.write_str("written") {
        success(_) => {},
        failure(_) => { return 12 }
    }
    if !writer.eq(os_string_from_text("written")) { return 13 }
    if !default_value<read OsStr from static>().is_empty() { return 14 }
    0
}
