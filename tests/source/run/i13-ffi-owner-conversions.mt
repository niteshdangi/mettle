// profiles: debug release
import alloc.borrow.BorrowedOrOwned
import alloc.boxed.Box
import alloc.vec
import alloc.vec.List
import core.borrow.ToOwned
import core.clone.Clone
import core.cmp.PartialEq
import core.convert.From
import core.iter.{ExtendItems, FromItems}
import std.ffi.{CStr, CString, OsStr, OsString, bytes_equal, os_string_from_text}

fn main(): i32 {
    let cstr = unsafe { CStr.from_bytes_with_nul_unchecked("ab\u{0}".as_bytes()) }
    let owned = cstr.to_owned()
    let borrowed: BorrowedOrOwned<region static, CStr> = BorrowedOrOwned.Borrowed(read *cstr)
    let moved: BorrowedOrOwned<region static, CStr> = BorrowedOrOwned.Owned(cstr.to_owned())
    if !CStr.(PartialEq<BorrowedOrOwned<region static, CStr>>).eq(cstr, borrowed.clone()) { return 1 }
    if !CString.(PartialEq<BorrowedOrOwned<region static, CStr>>).eq(owned, moved.clone()) { return 2 }
    if !CString.(From<BorrowedOrOwned<region static, CStr>>).from(borrowed).eq(owned) { return 3 }
    if !CString.(From<BorrowedOrOwned<region static, CStr>>).from(moved).eq(owned) { return 4 }
    let boxed = Box<CStr>.(From<CString>).from(cstr.to_owned())
    if !CString.(From<Box<CStr>>).from(boxed).eq(owned) { return 5 }

    let word = std.ffi.os_str("ab".as_bytes())
    let os_borrowed: BorrowedOrOwned<region static, OsStr> = BorrowedOrOwned.Borrowed(read *word)
    let os_owned: BorrowedOrOwned<region static, OsStr> = BorrowedOrOwned.Owned(word.to_owned())
    if !OsString.(From<BorrowedOrOwned<region static, OsStr>>).from(os_borrowed.clone()).eq(os_string_from_text("ab")) { return 6 }
    let os_box = Box<OsStr>.(From<OsString>).from(os_string_from_text("ab"))
    if !OsString.(From<Box<OsStr>>).from(os_box).eq(os_string_from_text("ab")) { return 7 }

    let views: List<read OsStr from static> = List<read OsStr from static>.(From<[read OsStr from static; 2]>).from([word, word])
    if !OsString.(FromItems<read OsStr from static>).from_iter(views).eq(os_string_from_text("abab")) { return 8 }
    let mixed: List<BorrowedOrOwned<region static, OsStr>> =
        List<BorrowedOrOwned<region static, OsStr>>.(From<[BorrowedOrOwned<region static, OsStr>; 2]>).from([os_borrowed, os_owned])
    if !OsString.(FromItems<BorrowedOrOwned<region static, OsStr>>).from_iter(mixed).eq(os_string_from_text("abab")) { return 9 }
    var extended = os_string_from_text("x")
    let extension: List<read OsStr from static> = List<read OsStr from static>.(From<[read OsStr from static; 2]>).from([word, word])
    OsString.(ExtendItems<read OsStr from static>).extend(mut extended, extension)
    if !extended.eq(os_string_from_text("xabab")) { return 10 }
    let cow_extension: List<BorrowedOrOwned<region static, OsStr>> =
        List<BorrowedOrOwned<region static, OsStr>>.(From<[BorrowedOrOwned<region static, OsStr>; 2]>).from([BorrowedOrOwned.Borrowed(read *word), BorrowedOrOwned.Borrowed(read *word)])
    OsString.(ExtendItems<BorrowedOrOwned<region static, OsStr>>).extend(mut extended, cow_extension)
    if !extended.eq(os_string_from_text("xabababab")) { return 11 }
    0
}
