import std.ffi.CString

fn main(): i32 {
    let source: [u8; 3] = [109u8, 101u8, 116u8]
    let c_string = match take capture CString.new(source.to_vec()) {
        success(value) => value,
        failure(_) => { return 1 }
    }
    let bytes = alloc.vec.List<u8>.(core.convert.From<CString>).from(c_string)
    if bytes.len() != 3usize || bytes[0usize] != 109u8 || bytes[2usize] != 116u8 { return 2 }
    0
}
