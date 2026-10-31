// std::ffi CStr and CString: termination checks, counts, and owned conversions.
import std.ffi
import std.ffi.CString
import alloc.vec

fn main(): i32 {
    let good = [104u8, 105u8, 0u8]
    let view = match c_str_from_bytes_with_nul(good) {
        success(value) => value,
        failure(error) => { return 1 }
    }
    if view.count_bytes() != 2usize { return 2 }
    if view.to_bytes().len() != 2usize || view.to_bytes_with_nul().len() != 3usize { return 3 }
    if view.to_bytes()[0] != 104u8 { return 4 }
    if !view.to_str().is_present() { return 5 }

    let interior = [104u8, 0u8, 105u8, 0u8]
    match c_str_from_bytes_with_nul(interior) {
        success(value) => { return 6 },
        failure(error) => { if !error.interior || error.position != 1usize { return 7 } }
    }
    let open = [104u8, 105u8]
    match c_str_from_bytes_with_nul(open) {
        success(value) => { return 8 },
        failure(error) => { if error.interior { return 9 } }
    }

    match c_str_from_bytes_until_nul(interior) {
        present(value) => { if value.count_bytes() != 1usize { return 10 } },
        none => { return 10 }
    }
    match c_str_from_bytes_until_nul(open) {
        present(value) => { return 11 },
        none => {}
    }

    var owned_bytes = vec.new<u8>()
    owned_bytes.push(97u8)
    owned_bytes.push(0u8)
    let from_pointer = unsafe { c_str_from_ptr(owned_bytes.as_ptr()) }
    if from_pointer.count_bytes() != 1usize { return 12 }

    let made = match c_string_from_bytes(open) {
        success(value) => value,
        failure(error) => { return 13 }
    }
    if made.count_bytes() != 2usize { return 14 }
    if made.as_bytes_with_nul().len() != 3usize || made.as_bytes_with_nul()[2] != 0u8 { return 15 }
    let again = made.as_c_str().into_c_string()
    if again.count_bytes() != 2usize { return 16 }

    match c_string_from_bytes(interior) {
        success(value) => { return 17 },
        failure(error) => { if !error.interior { return 17 } }
    }

    var raw = vec.new<u8>()
    raw.push(98u8)
    let built = unsafe { CString.from_vec_unchecked(take raw) }
    if built.count_bytes() != 1usize || built.as_bytes_with_nul()[1] != 0u8 { return 18 }

    var terminated = vec.new<u8>()
    terminated.push(99u8)
    terminated.push(0u8)
    let checked = match CString.from_vec_with_nul(take terminated) {
        success(value) => value,
        failure(error) => { return 19 }
    }
    var stored = checked.into_bytes()
    if stored.len() != 1usize || stored[0] != 99u8 { return 20 }

    var terminated_box = vec.new<u8>()
    terminated_box.push(100u8)
    terminated_box.push(0u8)
    let boxed_source = unsafe { CString.from_vec_with_nul_unchecked(take terminated_box) }
    let boxed = boxed_source.into_boxed_c_str()
    if boxed.get().count_bytes() != 1usize { return 21 }
    0
}
