// profiles: debug release
import alloc.borrow.BorrowedOrOwned
import alloc.string.{String, ToString}
import core.cmp.{Ordering, PartialEq, PartialOrd}
import core.convert.From
import core.default.Default
import core.fmt
import core.iter.{Iterator, OwnedIterable}
import core.text.Text
import std.ffi.{CStr, CString, OsStr, OsString, bytes_equal}
import std.path.{Path, PathBuf, path_from_text, path_buf_from_text}

fn compares<L: PartialEq<R> + PartialOrd<R> + unsized, R: unsized>(
    read left: L, read right: R, expected: Ordering
): Unit {
    assert(L.(PartialEq<R>).eq(left, right) == expected.is_eq(), "equality follows content")
    assert(L.(PartialEq<R>).ne(left, right) != expected.is_eq(), "inequality agrees with equality")
    assert(L.(PartialOrd<R>).partial_cmp(left, right) == present(expected), "ordering follows content")
}

fn path_cows(): Unit {
    let borrowed: BorrowedOrOwned<region static, Path> =
        BorrowedOrOwned.Borrowed(path_from_text("/a//./b"))
    let owned: BorrowedOrOwned<region static, Path> =
        BorrowedOrOwned.Owned(path_buf_from_text("/a/b"))
    let path = path_from_text("/a/b")
    let buf = path_buf_from_text("/a/b")
    let os = OsStr.new("/a/b".as_bytes())
    let os_owner = OsString.(From<read Text from static>).from("/a/b")
    compares(path, borrowed, Ordering.Equal)
    compares(path, owned, Ordering.Equal)
    compares(buf, borrowed, Ordering.Equal)
    compares(buf, owned, Ordering.Equal)
    compares(os, borrowed, Ordering.Equal)
    compares(os_owner, owned, Ordering.Equal)
    compares(path_from_text("/a/a"), owned, Ordering.Less)
    compares(path_buf_from_text("/a/c"), borrowed, Ordering.Greater)
    let copied = PathBuf.(From<BorrowedOrOwned<region static, Path>>).from(take borrowed)
    assert(bytes_equal(copied.as_bytes(), "/a//./b".as_bytes()), "borrowed path conversion preserves spelling")
    let owned_pointer = owned.as_ref().as_bytes().as_ptr()
    let moved = PathBuf.(From<BorrowedOrOwned<region static, Path>>).from(take owned)
    assert(moved.as_bytes().as_ptr() == owned_pointer, "owned path conversion transfers storage")
    var iter = (read moved).into_iter()
    assert(iter.next().or_panic().same(OsStr.new("/".as_bytes())), "borrowed owner iteration starts at root")
    assert(iter.next_back().or_panic().same(OsStr.new("b".as_bytes())), "borrowed owner iterator supports mixed ends")
    assert(iter.next().or_panic().same(OsStr.new("a".as_bytes())) && iter.next().is_none(),
        "borrowed owner iteration yields each remaining component once")
    var path_iter = path.into_iter()
    assert(path_iter.count() == 3usize, "borrowed path implements the owned-view iteration protocol")
}

fn os_cows(): Unit {
    let borrowed: BorrowedOrOwned<region static, OsStr> =
        BorrowedOrOwned.Borrowed(OsStr.new("/a//./b".as_bytes()))
    let owned: BorrowedOrOwned<region static, OsStr> =
        BorrowedOrOwned.Owned(OsString.(From<read Text from static>).from("/a/b"))
    let path = path_from_text("/a/b")
    let buf = path_buf_from_text("/a/b")
    let path_cow: BorrowedOrOwned<region static, Path> =
        BorrowedOrOwned.Borrowed(path_from_text("/a/b"))
    compares(path, borrowed, Ordering.Equal)
    compares(buf, owned, Ordering.Equal)
    compares(OsStr.new("/a/b".as_bytes()), borrowed, Ordering.Greater)
    compares(OsString.(From<read Text from static>).from("/a/b"), owned, Ordering.Equal)
    compares(OsStr.new("/a/b".as_bytes()), owned, Ordering.Equal)
    compares(OsString.(From<read Text from static>).from("/a/a"), owned, Ordering.Less)
    compares<OsStr, BorrowedOrOwned<region static, Path>>(
        OsStr.new("/a/b".as_bytes()), path_cow, Ordering.Equal)
    compares<OsString, BorrowedOrOwned<region static, Path>>(
        OsString.(From<read Text from static>).from("/a/b"), path_cow, Ordering.Equal)
    var mutable = path_buf_from_text("base")
    {
        let native = mutable.as_mut_os_string()
        native.push(OsStr.new("/child".as_bytes()))
        native.reserve(32usize)
    }
    assert(mutable.as_path() == path_from_text("base/child") && mutable.capacity() >= 42usize,
        "exclusive native owner mutation updates the path's storage and capacity")
    mutable.push(path_from_text("tail"))
    assert(mutable.as_path() == path_from_text("base/child/tail"), "path operations resume after the native loan")
}

fn equality(): Unit {
    let text: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("a\u{e9}")
    let owned_text: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Owned(String("a\u{e9}"))
    assert(String("a\u{e9}").eq(text) && String("a\u{e9}").eq(owned_text) &&
        !String("other").eq(owned_text), "string comparison handles both ownership alternatives")
    let cstr = unsafe { CStr.from_bytes_with_nul_unchecked("a\u{e9}\u{0}".as_bytes()) }
    let borrowed: BorrowedOrOwned<region static, CStr> = BorrowedOrOwned.Borrowed(cstr)
    let owned: BorrowedOrOwned<region static, CStr> = BorrowedOrOwned.Owned(cstr.to_owned())
    let different = CString.default()
    assert(cstr.eq(borrowed) && cstr.eq(owned) && cstr.to_owned().eq(borrowed) &&
        cstr.to_owned().eq(owned) && !different.eq(owned), "C string comparison ignores allocation identity")
}

fn display<D: fmt.Display>(read value: D, read expected: Text): Unit {
    assert(value.to_string().as_text() == expected, "display renders replacement text")
    var storage: [u8; 0] = []
    var output = fmt.buffer_writer(mut storage)
    var formatter = fmt.formatter(mut output, fmt.spec())
    assert((capture value.fmt(mut formatter)).is_failure(), "display propagates writer failure")
}

fn reference_relations(
    read path: Path, read buf: PathBuf, read os: OsStr, read owner: OsString, expected: Ordering
): Unit {
    let target_path = path_from_text("/a/b")
    let target_buf = path_buf_from_text("/a/b")
    let target_os = OsStr.new("/a/b".as_bytes())
    let target_owner = OsString.(From<read Text from static>).from("/a/b")
    let target_text: read Text = "/a/b"
    let path_cow: BorrowedOrOwned<region static, Path> = BorrowedOrOwned.Borrowed(target_path)
    let os_cow: BorrowedOrOwned<region static, OsStr> = BorrowedOrOwned.Borrowed(target_os)
    compares<OsStr, OsStr>(os, target_os, expected)
    compares<read Path, OsStr>(read path, target_os, expected)
    compares<read Path, OsString>(read path, target_owner, expected)
    compares<read Path, PathBuf>(read path, target_buf, expected)
    compares<Path, read OsStr>(path, read target_os, expected)
    compares<PathBuf, read OsStr>(buf, read target_os, expected)
    compares<OsStr, read Path>(os, read target_path, expected)
    compares<OsString, read Path>(owner, read target_path, expected)
    compares<read OsStr, Path>(read os, target_path, expected)
    compares<read OsStr, PathBuf>(read os, target_buf, expected)
    compares<read OsStr, OsString>(read os, target_owner, expected)
    compares<OsString, read OsStr>(owner, read target_os, expected)
    compares<OsString, read Text>(owner, read target_text, expected)
    compares<PathBuf, read Path>(buf, read target_path, expected)
    compares<read Path, BorrowedOrOwned<region static, Path>>(read path, path_cow, expected)
    compares<read Path, BorrowedOrOwned<region static, OsStr>>(read path, os_cow, expected)
    compares<read OsStr, BorrowedOrOwned<region static, Path>>(read os, path_cow, expected)
    compares<read OsStr, BorrowedOrOwned<region static, OsStr>>(read os, os_cow, expected)
    assert(OsStr.(core.cmp.Ord).cmp(os, target_os) == expected, "native OS ordering agrees with equality")
}

fn main(): i32 {
    path_cows()
    os_cows()
    equality()
    reference_relations(path_from_text("/a/b"), path_buf_from_text("/a/b"),
        OsStr.new("/a/b".as_bytes()), OsString.(From<read Text from static>).from("/a/b"), Ordering.Equal)
    reference_relations(path_from_text("/a/a"), path_buf_from_text("/a/a"),
        OsStr.new("/a/a".as_bytes()), OsString.(From<read Text from static>).from("/a/a"), Ordering.Less)
    let same_c = unsafe { CStr.from_bytes_with_nul_unchecked("a\u{0}".as_bytes()) }
    let other_c = unsafe { CStr.from_bytes_with_nul_unchecked("b\u{0}".as_bytes()) }
    let c_owner = same_c.to_owned()
    assert(CStr.(PartialEq<read CStr>).eq(same_c, read same_c) &&
        !CStr.(PartialEq<read CStr>).eq(same_c, read other_c), "reference RHS C strings compare payload")
    assert(CString.(PartialEq<read CStr>).eq(c_owner, read same_c) &&
        !CString.(PartialEq<read CStr>).eq(c_owner, read other_c), "owned C strings compare reference RHS payload")
    let same_text: read Text = "a"
    let other_text: read Text = "b"
    let string_owner = String("a")
    assert(String.(PartialEq<read Text>).eq(string_owner, read same_text) &&
        !String.(PartialEq<read Text>).eq(string_owner, read other_text), "owned text compares reference RHS payload")
    let native = std.ffi.os_string_from_bytes([65u8, 0xffu8, 66u8])
    display(native.display(), "A\u{fffd}B")
    display(std.path.path([65u8, 0xffu8, 66u8]).display(), "A\u{fffd}B")
    display(path_buf_from_text("valid/path").display(), "valid/path")
    assert(bytes_equal(native.as_bytes(), [65u8, 0xffu8, 66u8]), "display does not alter native bytes")
    0
}
