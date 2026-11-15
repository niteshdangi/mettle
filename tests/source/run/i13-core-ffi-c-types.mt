fn main(): i32 {
    let char_value: std.ffi.c_char = 0
    let signed_char: std.ffi.c_schar = 0
    let unsigned_char: std.ffi.c_uchar = 0
    let short: std.ffi.c_short = 0
    let unsigned_short: std.ffi.c_ushort = 0
    let int: std.ffi.c_int = 0
    let unsigned_int: std.ffi.c_uint = 0
    let long: std.ffi.c_long = 0
    let unsigned_long: std.ffi.c_ulong = 0
    let long_long: std.ffi.c_longlong = 0
    let unsigned_long_long: std.ffi.c_ulonglong = 0
    let float: std.ffi.c_float = 0.0
    let double: std.ffi.c_double = 0.0
    let void_pointer: ptr<read std.ffi.c_void> = core.ptr.null<std.ffi.c_void>()
    let _ = char_value
    let _ = signed_char
    let _ = unsigned_char
    let _ = short
    let _ = unsigned_short
    let _ = int
    let _ = unsigned_int
    let _ = long
    let _ = unsigned_long
    let _ = long_long
    let _ = unsigned_long_long
    let _ = float
    let _ = double
    let _ = void_pointer
    0
}
