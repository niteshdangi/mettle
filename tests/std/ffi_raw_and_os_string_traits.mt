// CString raw hand-off, and OsStr/OsString comparison, hashing, cloning and conversion.
import core.hash.hash_one
import core.clone.Clone
import core.default.Default
import core.cmp.Ordering
import core.borrow.{Borrow, ToOwned}
import core.convert.From
import std.ffi.{CString, OsStr, OsString}
import alloc.string

fn raw_round_trip(): i32 throws std.ffi.CStrError {
    let original = try CString.new([104u8, 105u8])
    let raw = original.into_raw()
    if unsafe { *raw } != 104u8 || unsafe { *raw.add(2usize) } != 0u8 { return 1 }
    let rebuilt = unsafe { CString.from_raw(raw) }
    if rebuilt.count_bytes() != 2usize || rebuilt.to_bytes_with_nul().len() != 3usize { return 2 }
    if rebuilt.to_bytes()[1usize] != 105u8 { return 3 }
    let empty = unsafe { CString.from_raw(CString.default().into_raw()) }
    if !empty.is_empty() { return 4 }
    0
}

fn os_strings(): i32 {
    let abc = OsString.from(string.String.(From<char>).from('a'))
    var pushed = OsString.new()
    pushed.push_bytes([97u8])
    if abc != pushed || abc.clone() != abc { return 10 }
    if hash_one(read abc) != hash_one(read pushed) { return 11 }
    if hash_one(read abc.as_os_str()) != hash_one(read abc) { return 12 }
    let b = OsString.from_encoded_bytes_unchecked(alloc.vec.from_array([98u8]))
    if abc.cmp(b) != Ordering.Less || b.cmp(abc) != Ordering.Greater { return 13 }
    if abc.as_os_str().cmp(abc.as_os_str()) != Ordering.Equal { return 14 }
    if abc.as_os_str() == b.as_os_str() { return 15 }
    let owned = abc.as_os_str().to_owned()
    if owned != abc { return 16 }
    if abc.borrow().len() != 1usize { return 17 }
    if !OsString.default().is_empty() { return 18 }
    0
}

fn main(): i32 {
    let first = capture raw_round_trip()
    match take first {
        success(code) => { if code != 0 { return code } },
        failure(_) => { return 99 }
    }
    os_strings()
}
