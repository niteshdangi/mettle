// profiles: debug release
// Windows OsString UTF-16/WTF-8 round-trips and cloned wide iterators.

@cfg(target_os = "windows")
import std.ffi.OsString
@cfg(target_os = "windows")
import std.os.windows.ffi.{OsStrExt, OsStringExt}
@cfg(target_os = "windows")
import core.clone.Clone

@cfg(target_os = "windows")
fn main(): i32 {
    let wide: [u16; 6] = [
        97u16,
        0xd800u16,
        0u16,
        0xdc00u16,
        0xd83du16,
        0xde00u16
    ]
    let value = OsString.(OsStringExt).from_wide(wide.as_slice())
    let expected_bytes: [u8; 12] = [
        0x61u8,
        0xedu8, 0xa0u8, 0x80u8,
        0u8,
        0xedu8, 0xb0u8, 0x80u8,
        0xf0u8, 0x9fu8, 0x98u8, 0x80u8
    ]
    if !std.ffi.bytes_equal(value.as_bytes(), expected_bytes.as_slice()) { return 6 }
    var encoded = value.as_os_str().encode_wide()
    var index = 0usize
    while index < 5usize {
        match encoded.next() {
            present(unit) => { if unit != wide[index] { return 1 } },
            none => { return 1 }
        }
        index += 1usize
    }
    match encoded.next() {
        present(unit) => { if unit != 0xd83du16 { return 2 } },
        none => { return 2 }
    }
    var clone = encoded.clone()
    match encoded.next() {
        present(unit) => { if unit != 0xde00u16 { return 3 } },
        none => { return 3 }
    }
    match clone.next() {
        present(unit) => { if unit != 0xde00u16 { return 4 } },
        none => { return 4 }
    }
    if encoded.next().is_present() || clone.next().is_present() { return 5 }

    let high: [u16; 1] = [0xd83du16]
    let low: [u16; 1] = [0xde00u16]
    var joined = OsString.(OsStringExt).from_wide(high.as_slice())
    let trailing = OsString.(OsStringExt).from_wide(low.as_slice())
    joined.push(trailing.as_os_str())
    let pair_bytes: [u8; 4] = [0xf0u8, 0x9fu8, 0x98u8, 0x80u8]
    if !std.ffi.bytes_equal(joined.as_bytes(), pair_bytes.as_slice()) { return 7 }
    0
}

@cfg(not(target_os = "windows"))
fn main(): i32 { 0 }
