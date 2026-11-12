// profiles: debug release
import alloc.borrow.BorrowedOrOwned
import alloc.boxed.Box
import alloc.string.String
import alloc.vec
import core.borrow.AsRef
import core.cmp.PartialEq
import core.convert.{From, TryFrom}
import core.default.Default
import core.iter.{ExtendItems, FromItems}
import core.panic.panic
import core.text.Text
import std.ffi.{CStr, CString, OsStr, OsString, bytes_equal, os_string_from_bytes}

type OsInput { value: OsString }
extend OsInput implements AsRef<OsStr> {
    fn as_ref(): read OsStr from self { self.value.as_os_str() }
}

fn text(): Unit {
    let borrowed: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Borrowed("a\u{e9}")
    let copied = String.(From<BorrowedOrOwned<region static, Text>>).from(take borrowed)
    assert(copied.as_text() == "a\u{e9}", "borrowed text conversion copies UTF-8")
    let owner = String("owned")
    let pointer = owner.as_ptr()
    let owned: BorrowedOrOwned<region static, Text> = BorrowedOrOwned.Owned(owner)
    let moved = String.(From<BorrowedOrOwned<region static, Text>>).from(take owned)
    assert(moved.as_ptr() == pointer, "owned text conversion transfers its buffer")
    var mutable = String("mutable")
    let mut_view = String.(From<mut Text>).from(mutable.as_mut_str())
    assert(mut_view.as_text() == "mutable", "exclusive text conversion copies its bytes")

    var pieces = vec.new<BorrowedOrOwned<region static, Text>>()
    pieces.push(BorrowedOrOwned.Borrowed("a"))
    pieces.push(BorrowedOrOwned.Owned(String("\u{e9}")))
    let joined = String.(FromItems<BorrowedOrOwned<region static, Text>>).from_iter(take pieces)
    assert(joined.as_text() == "a\u{e9}", "collection handles borrowed and owned text")
    var tail = vec.new<BorrowedOrOwned<region static, Text>>()
    tail.push(BorrowedOrOwned.Owned(String("!")))
    tail.push(BorrowedOrOwned.Borrowed("?"))
    var extended = joined
    String.(ExtendItems<BorrowedOrOwned<region static, Text>>).extend(mut extended, take tail)
    assert(extended.as_text() == "a\u{e9}!?", "extension preserves item order")
}

fn c_strings(): Unit {
    let terminated = [255u8, 65u8, 0u8]
    let value = unsafe { CString.from_vec_with_nul_unchecked(os_string_from_bytes(terminated).into_bytes()) }
    let boxed = value.into_boxed_c_str()
    let pointer = boxed.get().as_ptr()
    let restored = CString.(From<Box<CStr>>).from(take boxed)
    assert(restored.as_ptr() == pointer && bytes_equal(restored.as_bytes_with_nul(), terminated),
        "boxed C strings transfer arbitrary terminated bytes")
    let raw = restored.into_raw()
    unsafe { *raw.add(1usize) = 90i8 }
    let recovered = unsafe { CString.from_raw(raw) }
    assert(bytes_equal(recovered.as_bytes_with_nul(), [255u8, 90u8, 0u8]),
        "raw reconstruction retains foreign non-NUL writes")
    let boxed_again = recovered.into_boxed_c_str()
    let pointer_again = boxed_again.get().as_ptr()
    let from_method = boxed_again.into_c_string()
    assert(from_method.as_ptr() == pointer_again, "boxed method consumes without copying")
    let owned: BorrowedOrOwned<region static, CStr> = BorrowedOrOwned.Owned(from_method)
    let moved = CString.(From<BorrowedOrOwned<region static, CStr>>).from(take owned)
    assert(moved.as_ptr() == pointer_again, "owned C string conversion transfers its buffer")
    let replaced = moved.to_string_lossy()
    assert(replaced.is_owned() && replaced.as_ref() == "\u{fffd}Z",
        "invalid C bytes allocate replacement text without their terminator")
    let borrowed_view = unsafe { CStr.from_bytes_with_nul_unchecked("borrowed\u{0}".as_bytes()) }
    let borrowed_lossy = borrowed_view.to_string_lossy()
    assert(borrowed_lossy.is_borrowed() &&
        borrowed_lossy.as_ref().as_bytes().as_ptr() == borrowed_view.to_bytes().as_ptr(),
        "valid C UTF-8 conversion lends the original bytes")
    match take borrowed_view.to_str() {
        success(value) => assert(value == "borrowed", "checked C UTF-8 conversion lends text"),
        failure(_) => panic("valid C UTF-8 was rejected")
    }
    let borrowed: BorrowedOrOwned<region static, CStr> = BorrowedOrOwned.Borrowed(borrowed_view)
    let copied = CString.(From<BorrowedOrOwned<region static, CStr>>).from(take borrowed)
    assert(CString.(PartialEq<CStr>).eq(copied, borrowed_view),
        "borrowed C string conversion preserves content")

    let empty_raw = CString.default().into_raw()
    let empty = unsafe { CString.from_raw(empty_raw) }
    assert(empty.is_empty() && empty.as_bytes_with_nul().len() == 1usize,
        "empty raw C strings retain their single terminator")
    let valid = unsafe { CString.from_vec_unchecked(os_string_from_bytes("valid".as_bytes()).into_bytes()) }
    let valid_pointer = valid.as_ptr().cast<u8>()
    match take String.(TryFrom<CString>).try_from(take valid) {
        success(converted) => assert(converted.as_ptr() == valid_pointer && converted.as_text() == "valid",
            "checked UTF-8 conversion transfers a valid buffer"),
        failure(_) => panic("valid C string was rejected")
    }
    let invalid = unsafe { CString.from_vec_unchecked(os_string_from_bytes([65u8, 0xe9u8]).into_bytes()) }
    let invalid_pointer = invalid.as_ptr()
    match take String.(TryFrom<CString>).try_from(take invalid) {
        success(_) => panic("invalid UTF-8 was accepted"),
        failure(error) => {
            assert(error.utf8_error().valid_up_to() == 1usize && error.utf8_error().error_len().is_none(),
                "conversion error preserves the incomplete UTF-8 sequence")
            let original = error.into_cstring()
            assert(original.as_ptr() == invalid_pointer &&
                bytes_equal(original.as_bytes_with_nul(), [65u8, 0xe9u8, 0u8]),
                "failed conversion returns the unchanged allocation")
        }
    }
}

fn os_strings(): Unit {
    let input = OsInput(os_string_from_bytes([255u8, 0u8, 65u8]))
    let copied = OsString.(From<read OsInput>).from(read input)
    assert(bytes_equal(copied.as_bytes(), input.value.as_bytes()), "generic OS view conversion copies every byte")
    let native_text = copied.to_string_lossy()
    assert(native_text.is_owned() && native_text.as_ref() == "\u{fffd}\u{0}A",
        "lossy OS conversion preserves embedded NUL bytes")
    let valid = OsString.(From<read Text from static>).from("valid")
    let valid_text = valid.to_string_lossy()
    assert(valid_text.is_borrowed() && valid_text.as_ref().as_bytes().as_ptr() == valid.as_bytes().as_ptr(),
        "valid native UTF-8 conversion borrows its owner")
    let boxed = copied.into_boxed_os_str()
    let pointer = boxed.get().as_bytes().as_ptr()
    let restored = OsString.(From<Box<OsStr>>).from(take boxed)
    assert(restored.as_bytes().as_ptr() == pointer, "boxed OS strings transfer their allocation")
    let boxed_again = restored.into_boxed_os_str()
    let pointer_again = boxed_again.get().as_bytes().as_ptr()
    let restored_again = boxed_again.into_os_string()
    assert(restored_again.as_bytes().as_ptr() == pointer_again, "boxed OS method transfers its allocation")
    let owned: BorrowedOrOwned<region static, OsStr> = BorrowedOrOwned.Owned(restored_again)
    let moved = OsString.(From<BorrowedOrOwned<region static, OsStr>>).from(take owned)
    assert(moved.as_bytes().as_ptr() == pointer_again, "owned OS conversion does not copy")
    let borrowed: BorrowedOrOwned<region static, OsStr> =
        BorrowedOrOwned.Borrowed(OsStr.new("borrowed".as_bytes()))
    let from_borrow = OsString.(From<BorrowedOrOwned<region static, OsStr>>).from(take borrowed)
    assert(bytes_equal(from_borrow.as_bytes(), "borrowed".as_bytes()), "borrowed OS conversion copies content")
    let c_string = unsafe { CString.from_vec_unchecked(os_string_from_bytes([255u8, 65u8]).into_bytes()) }
    let c_pointer = c_string.as_ptr().cast<u8>()
    let os = OsString.(From<CString>).from(take c_string)
    assert(os.as_bytes().as_ptr() == c_pointer && bytes_equal(os.as_bytes(), [255u8, 65u8]),
        "C to OS conversion transfers storage and removes only its terminator")
    let empty_box = OsString.new().into_boxed_os_str()
    assert(empty_box.into_os_string().is_empty(), "empty boxed OS strings remain valid")
    var pieces = vec.new<BorrowedOrOwned<region static, OsStr>>()
    pieces.push(BorrowedOrOwned.Borrowed(OsStr.new("a".as_bytes())))
    pieces.push(BorrowedOrOwned.Owned(os_string_from_bytes([255u8, 0u8])))
    let joined = OsString.(FromItems<BorrowedOrOwned<region static, OsStr>>).from_iter(take pieces)
    assert(bytes_equal(joined.as_bytes(), [97u8, 255u8, 0u8]), "OS collection preserves non-Unicode and NUL bytes")
    var tail = vec.new<BorrowedOrOwned<region static, OsStr>>()
    tail.push(BorrowedOrOwned.Owned(os_string_from_bytes([66u8])))
    tail.push(BorrowedOrOwned.Borrowed(OsStr.new("c".as_bytes())))
    var extended = joined
    OsString.(ExtendItems<BorrowedOrOwned<region static, OsStr>>).extend(mut extended, take tail)
    assert(bytes_equal(extended.as_bytes(), [97u8, 255u8, 0u8, 66u8, 99u8]),
        "OS extension appends both ownership alternatives in order")
}

fn main(): i32 {
    text()
    c_strings()
    os_strings()
    0
}
