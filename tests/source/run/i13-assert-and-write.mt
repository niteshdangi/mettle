import core.fmt
import core.panic

fn main(): i32 {
    panic.assert(true, "kept")
    panic.assert_eq(1, 1, "eq")
    panic.assert_ne(1, 2, "ne")
    panic.debug_assert(true, "debug")
    panic.debug_assert_eq(3, 3, "debug eq")
    panic.debug_assert_ne(3, 4, "debug ne")

    var buf = [0u8; 8]
    var writer = fmt.buffer_writer(buf)
    match capture fmt.write(mut writer, "ab") {
        success(_) => {},
        failure(_) => { return 1 }
    }
    if writer.len() != 2usize { return 2 }
    match capture fmt.writeln(mut writer, "c") {
        success(_) => {},
        failure(_) => { return 3 }
    }
    if writer.len() != 4usize { return 4 }
    match fmt.written_text(buf, writer.len()) {
        present(text) => { if text != "ab\nc\n" { return 5 } },
        none => { return 5 }
    }
    0
}
