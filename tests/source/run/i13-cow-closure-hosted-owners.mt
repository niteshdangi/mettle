import alloc.borrow.BorrowedOrOwned
import std.ffi.{CStr, OsStr}
import std.path.Path

fn c_string<region r>(read source: CStr from r): i32 {
    var cow: BorrowedOrOwned<region r, CStr> =
        BorrowedOrOwned.Borrowed(read source)
    let address = cow.to_mut().as_ptr()
    if !cow.is_owned() || cow.as_ref().count_bytes() != 2usize { return 1 }
    let moved = cow.into_owned()
    if moved.as_ptr() != address || moved.as_bytes()[1usize] != 105u8 {
        return 2
    }
    0
}

fn os_string<region r>(read source: OsStr from r): i32 {
    var cow: BorrowedOrOwned<region r, OsStr> =
        BorrowedOrOwned.Borrowed(read source)
    if cow.to_mut().as_bytes()[0usize] != 255u8 { return 3 }
    if !cow.is_owned() || cow.as_ref().len() != 2usize { return 4 }
    let moved = cow.into_owned()
    if moved.as_bytes()[0usize] != 255u8 || moved.as_bytes()[1usize] != 120u8 {
        return 5
    }
    0
}

fn path<region r>(read source: Path from r): i32 {
    var cow: BorrowedOrOwned<region r, Path> =
        BorrowedOrOwned.Borrowed(read source)
    if cow.to_mut().as_bytes()[0usize] != 255u8 { return 6 }
    if !cow.is_owned() || cow.as_ref().as_bytes().len() != 2usize { return 7 }
    let moved = cow.into_owned()
    if moved.as_bytes()[0usize] != 255u8 || moved.as_bytes()[1usize] != 120u8 {
        return 8
    }
    0
}

fn main(): i32 {
    let terminated = [104u8, 105u8, 0u8]
    let source = match capture CStr.from_bytes_with_nul(read terminated) {
        success(value) => value,
        failure(_) => { return 9 }
    }
    let result = c_string(source)
    if result != 0 { return result }
    if terminated[0usize] != 104u8 || terminated[2usize] != 0u8 { return 10 }

    let bytes = [255u8, 120u8]
    let result = os_string(std.ffi.os_str(read bytes))
    if result != 0 { return result }
    let result = path(std.path.path(read bytes))
    if result != 0 { return result }
    if bytes[0usize] != 255u8 { return 11 }
    0
}
