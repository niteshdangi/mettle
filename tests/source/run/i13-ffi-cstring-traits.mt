// profiles: debug release
module source_helpers;
import core.borrow.{AsRef, Borrow, ToOwned}
import core.clone.Clone
import core.cmp.{Ord, PartialEq}
import core.convert.From
import core.default.Default
import core.fmt.Debug
import core.iter.{range_from, RangeFull, range_full}
import core.iter.FromItems
import core.num.NonZero
import core.ops.{Deref, Index}
import core.text.FromStr
import alloc.vec
import alloc.vec.List
import std.panic.{catch_panic, CatchResult}
import std.ffi.{CStr, CString, os_string_from_bytes}

fn debug_is<T: Debug + unsized>(read value: T, read expected: Text): bool {
    source_helpers.debug_is!(T, value, expected)
}

fn checks_borrow<region r>(read value: CString from r): bool {
    let borrowed = CString.(Borrow<CStr>).borrow(value)
    let referenced = CString.(AsRef<CStr>).as_ref(value)
    CStr.(PartialEq).eq(borrowed, referenced) &&
        CStr.(PartialEq<read CStr>).eq(borrowed, read referenced) &&
        CString.(PartialEq<read CStr>).eq(value, read referenced) &&
        borrowed.to_bytes()[0usize] == 65u8
}

fn main(): i32 {
    let bytes: [u8; 4] = [65u8, 66u8, 67u8, 0u8]
    let checked = match take capture CStr.from_bytes_with_nul(bytes) {
        success(value) => value,
        failure(_) => { return 1 }
    }
    let native: read core.ffi.CStr = checked
    let allocated: alloc.ffi.CString = native.to_owned()
    let owned: std.ffi.CString = allocated
    if !CString.(PartialEq<CStr>).eq(owned, checked) || owned.cmp(owned).is_ne() { return 2 }
    if !checked.eq(owned) { return 25 }
    let static_cstr = match take capture CStr.from_bytes_with_nul("ABC\u{0}".as_bytes()) {
        success(value) => value,
        failure(_) => { return 26 }
    }
    let from_cstr = CString.(From<read CStr from static>).from(static_cstr)
    if !from_cstr.eq(owned) { return 23 }
    if !checks_borrow(read owned) { return 3 }
    if !CStr.(PartialEq).eq(CString.(Deref).deref(owned), checked) { return 16 }
    let full_view = CString.(Index<RangeFull>).index(owned, range_full())
    if !std.ffi.bytes_equal(full_view.to_bytes_with_nul(), bytes) { return 4 }
    if !std.ffi.bytes_equal(checked[range_from(1usize)].to_bytes(), [66u8, 67u8]) { return 5 }
    let end_index = catch_panic(fn(): Unit {
        let _ = CStr.(Index<core.iter.RangeFrom<usize>>).index(checked, range_from(4usize))
    })
    match end_index {
        CatchResult.Panicked(info) => if info.code() != 101 { return 21 },
        _ => { return 22 }
    }

    let checked_unchecked = unsafe { CStr.from_bytes_with_nul_unchecked(bytes) }
    if !CStr.(PartialEq).eq(checked_unchecked, checked) { return 6 }
    if !debug_is(checked, "CStr(\"ABC\")") || !debug_is(owned, "CString(\"ABC\")") { return 27 }
    let duplicate = owned.clone()
    if !duplicate.eq(owned) || duplicate.as_ptr() == owned.as_ptr() { return 28 }
    if !checked.into_c_string().eq(owned) { return 7 }

    let from_vec = unsafe {
        CString.from_vec_unchecked(os_string_from_bytes([65u8, 66u8, 67u8]).into_bytes())
    }
    if !from_vec.eq(owned) { return 8 }
    let from_vec_with_nul = unsafe {
        CString.from_vec_with_nul_unchecked(os_string_from_bytes(bytes).into_bytes())
    }
    if !from_vec_with_nul.eq(owned) { return 9 }
    var nonzero_items = vec.new<NonZero<u8>>()
    nonzero_items.push(NonZero<u8>.new(65u8).unwrap())
    nonzero_items.push(NonZero<u8>.new(66u8).unwrap())
    nonzero_items.push(NonZero<u8>.new(67u8).unwrap())
    let nonzero_bytes = List<NonZero<u8>>.(FromItems<NonZero<u8>>).from_iter(nonzero_items)
    let from_nonzero = CString.(From<List<NonZero<u8>>>).from(nonzero_bytes)
    if !from_nonzero.eq(owned) { return 24 }
    let from_ptr = unsafe { CStr.from_ptr(owned.as_ptr()) }
    if !from_ptr.eq(owned) { return 10 }

    match take capture "A\u{0}B".parse<CString>() {
        success(_) => { return 11 },
        failure(_) => {}
    }
    match take capture "ABC".parse<CString>() {
        success(value) => {
            if !value.eq(owned) { return 12 }
        },
        failure(_) => { return 13 }
    }
    let empty = CString.default()
    if !empty.is_empty() || empty.count_bytes() != 0usize { return 14 }
    0
}
