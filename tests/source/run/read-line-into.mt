// Line reader contract: LF/CRLF kept, final unterminated line, none only at EOF,
// invalid UTF-8 -> InvalidData leaving an empty valid String.
import std.io.Reader
fn lines(read data: [u8]): i32 {
    var r = std.io.buf_reader(std.io.slice_reader(data))
    var buf = alloc.string.from_text("stale")
    var total = 0
    while true {
        match capture r.read_line_into(buf) {
            success(x) => match x {
                present(l) => { total = total * 10 + l.len() as i32 },
                none => { if buf.len() != 0usize { return -1 }; return total }
            },
            failure(e) => { return if buf.len() == 0usize { -2 } else { -3 } }
        }
    }
    total
}
fn main(): i32 {
    let ok = [97u8, 13u8, 10u8, 10u8, 99u8]
    let empty = [0u8; 0]
    let bad = [97u8, 10u8, 255u8, 10u8, 98u8]
    let multi = [0xc3u8, 0xa9u8, 10u8]
    if lines(ok) != 311 { return 1 }
    if lines(empty) != 0 { return 2 }
    if lines(bad) != -2 { return 3 }
    if lines(multi) != 3 { return 4 }
    0
}
