// CString and CStr: construction, equality, hashing, cloning and conversions.
import core.hash.hash_one
import core.clone.Clone
import core.default.Default
import std.ffi.{CString, CStr}

fn run(): i32 throws std.ffi.CStrError {
    let hello = try CString.new([104u8, 105u8])
    if hello.count_bytes() != 2usize || hello.is_empty() { return 1 }
    if hello.to_bytes().len() != 2usize || hello.to_bytes_with_nul().len() != 3usize { return 2 }
    if !hello.to_str().is_present() || hello.to_string_lossy().len() != 2usize { return 3 }
    let copy = hello.clone()
    if copy != hello || hash_one(read copy) != hash_one(read hello) { return 4 }
    if hello.as_c_str() != copy.as_c_str() { return 5 }
    let other = try CString.new([104u8, 111u8])
    if other == hello { return 6 }
    let empty = CString.default()
    if !empty.is_empty() || empty.count_bytes() != 0usize { return 7 }
    if unsafe { *hello.as_ptr() } != 104u8 || unsafe { *hello.as_c_str().as_ptr() } != 104u8 { return 8 }
    match CString.new([104u8, 0u8, 105u8]) {
        success(_) => { return 9 },
        failure(error) => { if !error.interior || error.position != 1usize { return 10 } }
    }
    match hello.into_string() {
        success(text) => { if text.len() != 2usize { return 11 } },
        failure(_) => { return 12 }
    }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(_) => 99
    }
}
