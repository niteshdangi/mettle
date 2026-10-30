// expect-error: ownership 11:54 live exclusive loan
// The returned line is a view of the buffer, so the buffer cannot be refilled while it lives.
import std::io::Read;
fn main(): i32 {
    let data = [97u8, 10u8, 98u8, 10u8]
    var r = std::io::buf_reader(std::io::slice_reader(data))
    var line = alloc::string::from_text("")
    match capture r.read_line_into(line) {
        success(x) => match x {
            present(l) => {
                let again = capture r.read_line_into(line)
                if l.len() == 2usize { return 0 }
            },
            none => {}
        },
        failure(e) => {}
    }
    1
}
