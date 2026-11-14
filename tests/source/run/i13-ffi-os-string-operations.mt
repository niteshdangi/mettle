// profiles: debug release
// OsString and OsStr: construction, byte and text views, mutation, ASCII case
// operations, lossy and checked conversion, and capacity management.

import core.iter.Iterator
import alloc.string.ToString
import std.ffi.{
    OsStr,
    OsString,
    os_str_from_text,
    os_str_mut,
    os_string_from_text,
    os_string_from_bytes
}

fn str_is(read s: OsStr, read want: Text): bool {
    match s.to_str() { present(t) => t == want, none => false }
}
fn string_is(read s: OsString, read want: Text): bool {
    match s.to_str() { present(t) => t == want, none => false }
}

fn checks_construction(): i32 {
    let empty = OsString.new()
    if !empty.is_empty() || empty.len() != 0usize || empty.capacity() != 0usize { return 1 }
    let sized = OsString.with_capacity(12usize)
    if sized.capacity() < 12usize || !sized.is_empty() { return 2 }
    let h: [u8; 1] = [0x68u8]
    let borrowed = OsStr.new(h)
    if borrowed.len() != 1usize { return 3 }
    let slice = os_str_from_text("hello")
    if slice.len() != 5usize || slice.as_bytes()[1usize] != 0x65u8 { return 4 }
    if !str_is(slice, "hello") || slice.display().to_string().as_text() != "hello" ||
        !std.ffi.bytes_equal(slice.as_encoded_bytes(), "hello".as_bytes()) { return 5 }
    let owned = slice.to_os_string()
    if !owned.as_os_str().same(slice) ||
        owned.display().to_string().as_text() != "hello" { return 6 }
    let copied = slice.into_os_string()
    if !copied.same(read owned) || copied.len() != 5usize { return 7 }
    let boxed = os_string_from_text("boxed").into_heap_os_str()
    if !boxed.get().same(os_str_from_text("boxed")) { return 8 }
    0
}

fn checks_mutation(): i32 {
    var s = OsString.new()
    s.push(os_str_from_text("ab"))
    s.push(os_str_from_text("cd"))
    if !string_is(s, "abcd") { return 10 }
    s.push_bytes([0x65u8, 0x66u8])
    if !string_is(s, "abcdef") || s.len() != 6usize { return 11 }
    s.make_ascii_uppercase()
    if !string_is(s, "ABCDEF") { return 12 }
    s.make_ascii_lowercase()
    if !string_is(s, "abcdef") { return 13 }
    let upper = s.to_ascii_uppercase()
    if !string_is(upper, "ABCDEF") || !string_is(s, "abcdef") { return 14 }
    let lower = os_string_from_text("MiXeD").to_ascii_lowercase()
    if !string_is(lower, "mixed") { return 15 }
    if !os_string_from_text("ABC").eq_ignore_ascii_case(read os_string_from_text("abc")) { return 16 }
    if os_string_from_text("ABC").eq_ignore_ascii_case(read os_string_from_text("abd")) { return 17 }
    if !s.is_ascii() || os_string_from_bytes([0xffu8]).is_ascii() { return 18 }
    let mixed_bytes: [u8; 4] = [65u8, 98u8, 0xffu8, 90u8]
    let mixed = OsStr.new(mixed_bytes)
    let folded_bytes: [u8; 4] = [97u8, 66u8, 0xffu8, 122u8]
    let folded = OsStr.new(folded_bytes)
    if !std.ffi.bytes_equal(mixed.as_encoded_bytes(), mixed_bytes) ||
        mixed.is_ascii() || !mixed.eq_ignore_ascii_case(folded) { return 19 }
    let mismatch_bytes: [u8; 4] = [97u8, 66u8, 0xfeu8, 122u8]
    if mixed.eq_ignore_ascii_case(OsStr.new(mismatch_bytes)) { return 20 }
    let owned_copy_source = os_string_from_text("copy")
    let copied = owned_copy_source.to_os_string()
    var changed = owned_copy_source
    changed.make_ascii_uppercase()
    if !string_is(copied, "copy") || !string_is(changed, "COPY") { return 21 }
    let view_lower = mixed.to_ascii_lowercase()
    let lower_bytes: [u8; 4] = [97u8, 98u8, 0xffu8, 122u8]
    if !std.ffi.bytes_equal(view_lower.as_bytes(), lower_bytes) { return 22 }
    let view_upper = mixed.to_ascii_uppercase()
    let upper_bytes: [u8; 4] = [65u8, 66u8, 0xffu8, 90u8]
    if !std.ffi.bytes_equal(view_upper.as_bytes(), upper_bytes) { return 23 }
    let lossy = mixed.to_string_lossy()
    if !lossy.is_owned() || lossy.as_ref() != "Ab\u{fffd}Z" { return 24 }
    if mixed.display().to_string().as_text() != "Ab\u{fffd}Z" { return 27 }
    var mutable_bytes: [u8; 4] = [65u8, 98u8, 0xffu8, 90u8]
    var mutable_view = os_str_mut(mut mutable_bytes)
    mutable_view.make_ascii_lowercase()
    if !std.ffi.bytes_equal(mutable_view.as_bytes(), lower_bytes) { return 25 }
    mutable_view.make_ascii_uppercase()
    if !std.ffi.bytes_equal(mutable_view.as_bytes(), upper_bytes) { return 26 }
    0
}

fn checks_capacity(): i32 {
    var s = OsString.with_capacity(2usize)
    s.reserve(20usize)
    if s.capacity() < 20usize { return 20 }
    s.reserve_exact(40usize)
    if s.capacity() < 40usize { return 21 }
    s.push(os_str_from_text("xyz"))
    s.shrink_to(10usize)
    if s.capacity() != 10usize || !string_is(s, "xyz") { return 23 }
    s.shrink_to_fit()
    if s.capacity() != 3usize || !string_is(s, "xyz") { return 22 }
    s.shrink_to(10usize)
    if s.capacity() != 3usize || !string_is(s, "xyz") { return 23 }
    match capture s.try_reserve(8usize) {
        success(_) => {},
        failure(_) => { return 24 }
    }
    match capture s.try_reserve_exact(8usize) {
        success(_) => {},
        failure(_) => { return 25 }
    }
    s.clear()
    if !s.is_empty() || s.len() != 0usize { return 26 }
    0
}

fn checks_conversion(): i32 {
    let valid = os_string_from_bytes([0x61u8, 0x62u8])
    match take capture valid.into_string() {
        success(text) => { if text.as_text() != "ab" { return 30 } },
        failure(_) => { return 31 }
    }
    let invalid = os_string_from_bytes([0x61u8, 0xffu8])
    let lossy = invalid.to_string_lossy()
    if lossy.as_ref() != "a\u{fffd}" || !lossy.is_owned() { return 32 }
    if invalid.to_str().is_present() { return 33 }
    match take capture invalid.into_string() {
        success(_) => { return 34 },
        failure(_) => {}
    }
    let raw = os_string_from_bytes([0x61u8, 0x62u8]).into_encoded_bytes()
    if raw.len() != 2usize || raw[1usize] != 0x62u8 { return 35 }
    let rebuilt = OsString.from_encoded_bytes_unchecked(raw)
    if !string_is(rebuilt, "ab") { return 36 }
    let z: [u8; 1] = [0x7au8]
    let view = OsStr.from_encoded_bytes_unchecked(z)
    if !str_is(view, "z") || view.is_empty() { return 37 }
    0
}

fn main(): i32 {
    let first = checks_construction()
    if first != 0 { return first }
    let second = checks_mutation()
    if second != 0 { return second }
    let third = checks_capacity()
    if third != 0 { return third }
    checks_conversion()
}
