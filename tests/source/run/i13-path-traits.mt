// profiles: debug release

import alloc.string.String
import alloc.boxed.Box
import alloc.vec
import core.borrow.{AsRef, Borrow, ToOwned}
import core.cmp.{Ordering, Ord, PartialEq, PartialOrd}
import core.convert.From
import core.default.Default
import core.fmt
import core.fmt.Debug
import core.hash.hash_one
import core.iter.{ExtendItems, FromItems, Iterator, OwnedIterable}
import core.text.FromStr
import std.ffi.{OsStr, OsString}
import std.path.{Path, PathBuf, path, path_from_text, path_buf_from_bytes, path_buf_from_text}

fn debug_text<T: Debug>(read value: T): String {
    var output = String("")
    var formatter = fmt.formatter(mut output, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => {}
    }
    output
}

fn copy_path_buf<region r>(read value: PathBuf from r): PathBuf {
    PathBuf.(From<read PathBuf from r>).from(read value)
}

fn compare_path<T: PartialEq<Path> + PartialOrd<Path>>(
    read value: T, read other: Path
): Ordering? {
    let order = T.(PartialOrd<Path>).partial_cmp(value, other)
    if T.(PartialEq<Path>).eq(value, other) != (order == present(Ordering.Equal)) {
        return none
    }
    if T.(PartialEq<Path>).ne(value, other) != (order != present(Ordering.Equal)) {
        return none
    }
    if T.(PartialOrd<Path>).lt(value, other) != (order == present(Ordering.Less)) {
        return none
    }
    if T.(PartialOrd<Path>).le(value, other) != (order != present(Ordering.Greater)) {
        return none
    }
    if T.(PartialOrd<Path>).gt(value, other) != (order == present(Ordering.Greater)) {
        return none
    }
    if T.(PartialOrd<Path>).ge(value, other) != (order != present(Ordering.Less)) {
        return none
    }
    order
}

fn main(): i32 {
    let first = path_from_text("/a//./b")
    let second = path_from_text("/a/b")
    let reflexive: read Path = Path.(AsRef<Path>).as_ref(second)
    if reflexive != second { return 59 }
    if first != second || first.cmp(second) != Ordering.Equal { return 1 }
    if !Path.(PartialOrd).partial_cmp(first, second).unwrap().is_eq() { return 2 }
    if hash_one(first) != hash_one(second) { return 3 }
    if first.to_owned() != second { return 5 }
    let path_os: read OsStr = Path.(AsRef<OsStr>).as_ref(first)
    if path_os.as_bytes().len() != 7usize { return 20 }
    if first != std.ffi.os_str_from_text("/a/b") { return 21 }
    if !Path.(PartialOrd<OsStr>).partial_cmp(
        first, std.ffi.os_str_from_text("/a/b")
    ).unwrap().is_eq() {
        return 22
    }
    let os_value = std.ffi.os_string_from_text("/a/b")
    let os_view = os_value.as_os_str()
    if OsStr.(AsRef<Path>).as_ref(os_view) != second { return 30 }
    if !OsStr.(PartialEq<Path>).eq(os_view, second) { return 31 }
    if OsString.(PartialOrd<Path>).partial_cmp(os_value, second) !=
        present(Ordering.Equal) { return 32 }
    if OsString.(AsRef<Path>).as_ref(os_value) != second { return 33 }
    if !String.(PartialEq<Path>).eq(String("/a/b"), second) { return 34 }

    let owned = first.to_path_buf()
    if copy_path_buf(read owned) != owned { return 39 }
    let os_str_value = std.ffi.os_str_from_text("/a/b")
    let os_string_value = std.ffi.os_string_from_text("/a/b")
    if !OsStr.(PartialEq<PathBuf>).eq(os_str_value, owned) { return 40 }
    if OsStr.(PartialOrd<PathBuf>).partial_cmp(os_str_value, owned) !=
        present(Ordering.Equal) { return 41 }
    if !OsString.(PartialEq<Path>).eq(os_string_value, second) { return 42 }
    if OsString.(PartialOrd<Path>).partial_cmp(os_string_value, second) !=
        present(Ordering.Equal) { return 43 }
    if !OsString.(PartialEq<PathBuf>).eq(os_string_value, owned) { return 44 }
    if OsString.(PartialOrd<PathBuf>).partial_cmp(os_string_value, owned) !=
        present(Ordering.Equal) { return 45 }
    if !Path.(PartialEq<OsString>).eq(second, os_string_value) { return 46 }
    if Path.(PartialOrd<OsString>).partial_cmp(second, os_string_value) !=
        present(Ordering.Equal) { return 47 }
    if !Path.(PartialEq<String>).eq(second, String("/a/b")) { return 48 }
    if Path.(PartialOrd<String>).partial_cmp(second, String("/a/b")) !=
        present(Ordering.Equal) { return 49 }
    if !Path.(PartialEq<Text>).eq(second, "/a/b") { return 50 }
    if Path.(PartialOrd<Text>).partial_cmp(second, "/a/b") !=
        present(Ordering.Equal) { return 51 }
    if !PathBuf.(PartialEq<OsStr>).eq(owned, os_str_value) { return 52 }
    if PathBuf.(PartialOrd<OsStr>).partial_cmp(owned, os_str_value) !=
        present(Ordering.Equal) { return 53 }
    if PathBuf.(PartialOrd<OsString>).partial_cmp(owned, os_string_value) !=
        present(Ordering.Equal) { return 54 }
    if !PathBuf.(PartialEq<String>).eq(owned, String("/a/b")) { return 55 }
    if PathBuf.(PartialOrd<String>).partial_cmp(owned, String("/a/b")) !=
        present(Ordering.Equal) { return 56 }
    if !PathBuf.(PartialEq<Text>).eq(owned, "/a/b") { return 57 }
    if PathBuf.(PartialOrd<Text>).partial_cmp(owned, "/a/b") !=
        present(Ordering.Equal) { return 58 }
    if compare_path(owned, path_from_text("/a/./b")) != present(Ordering.Equal) {
        return 61
    }
    if compare_path(owned, path_from_text("/a/c")) != present(Ordering.Less) {
        return 62
    }
    if compare_path(owned, path_from_text("/a/a")) != present(Ordering.Greater) {
        return 63
    }
    let raw_owned: [u8; 6] = [47u8, 97u8, 47u8, 255u8, 47u8, 46u8]
    let raw_equal: [u8; 4] = [47u8, 97u8, 47u8, 255u8]
    let raw_less: [u8; 4] = [47u8, 97u8, 47u8, 254u8]
    let nonunicode = path_buf_from_bytes(read raw_owned)
    if compare_path(nonunicode, path(read raw_equal)) != present(Ordering.Equal) {
        return 64
    }
    if compare_path(nonunicode, path(read raw_less)) != present(Ordering.Greater) {
        return 65
    }
    if String.(PartialOrd<PathBuf>).partial_cmp(
        String("/a/b"),
        owned
    ) != present(Ordering.Equal) { return 35 }
    if owned != PathBuf.(From<OsString>).from(std.ffi.os_string_from_text("/a/b")) {
        return 6
    }
    let converted_os: OsString =
        OsString.(From<PathBuf>).from(path_buf_from_text("/a//./b"))
    if converted_os != std.ffi.os_string_from_text("/a//./b") { return 25 }
    let boxed_path: Box<Path> = path_buf_from_text("/boxed/path").into_boxed_path()
    let boxed_roundtrip =
        PathBuf.(From<Box<Path>>).from(take boxed_path)
    if boxed_roundtrip.as_path() != path_from_text("/boxed/path") { return 26 }
    let boxed_from_trait =
        Box<Path>.(From<PathBuf>).from(path_buf_from_text("/trait/box"))
    let trait_roundtrip =
        PathBuf.(From<Box<Path>>).from(take boxed_from_trait)
    if trait_roundtrip.as_path() != path_from_text("/trait/box") { return 36 }
    let string_path: PathBuf = PathBuf.(From<String>).from(String("from/string"))
    if string_path.as_path() != path_from_text("from/string") { return 27 }
    let text_path: PathBuf =
        PathBuf.(From<read Text from static>).from("from/text")
    if text_path.as_path() != path_from_text("from/text") { return 28 }
    let second_input = second
    let path_copy: PathBuf =
        PathBuf.(From<read Path from static>).from(second_input)
    if path_copy.as_path() != second { return 37 }
    let os_path: PathBuf = PathBuf.(From<read OsStr from static>).from(
        std.ffi.os_str_from_text("/a/b")
    )
    if os_path.as_path() != second { return 38 }
    let leaked = path_buf_from_text("/leaked").leak()
    if leaked.as_bytes().len() != 7usize { return 29 }
    if PathBuf.(Borrow<Path>).borrow(owned) != second { return 7 }
    let as_path: read Path = PathBuf.(AsRef<Path>).as_ref(owned)
    let as_os: read OsStr = PathBuf.(AsRef<OsStr>).as_ref(owned)
    if as_path != second || as_os.as_bytes().len() != 7usize { return 8 }
    if owned != second || owned != std.ffi.os_string_from_text("/a/b") { return 23 }
    if owned.as_path().cmp(second) != Ordering.Equal { return 24 }
    if hash_one(owned) != hash_one(second) || debug_text(owned).is_empty() { return 9 }

    let defaulted = PathBuf.(Default).default()
    if !defaulted.is_empty() { return 10 }
    match capture PathBuf.(FromStr).from_str("relative/path") {
        success(value) => { if value.as_path() != path_from_text("relative/path") { return 11 } },
    }

    var pieces = vec.new<PathBuf>()
    pieces.push(path_buf_from_text("one"))
    pieces.push(path_buf_from_text("two"))
    let collected = PathBuf.(FromItems<PathBuf>).from_iter(take pieces)
    if collected.as_path() != path_from_text("one/two") { return 13 }
    var extended = path_buf_from_text("root")
    var more = vec.new<PathBuf>()
    more.push(path_buf_from_text("a"))
    more.push(path_buf_from_text("b"))
    PathBuf.(ExtendItems<PathBuf>).extend(mut extended, take more)
    if extended.as_path() != path_from_text("root/a/b") { return 14 }

    var path_parts = 0usize
    for part in second.iter() {
        if part.as_bytes().len() == 0usize { return 15 }
        path_parts += 1usize
    }
    if path_parts != 3usize { return 16 }
    var buf_parts = 0usize
    for part in owned.iter() {
        if part.as_bytes().len() == 0usize { return 17 }
        buf_parts += 1usize
    }
    if buf_parts != 3usize { return 18 }

    let string = String("text")
    let os_view: read OsStr = String.(AsRef<OsStr>).as_ref(string)
    if os_view.as_bytes().len() != 4usize { return 19 }
    if String.(AsRef<Path>).as_ref(string).as_bytes().len() != 4usize {
        return 60
    }
    0
}
