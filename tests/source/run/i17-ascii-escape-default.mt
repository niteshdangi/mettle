import core.ascii.escape_default
import core.fmt.{Debug, Display, buffer_writer, formatter, spec, written_text}
import core.iter.{BidirectionalIterator, ExactSizeIterator, Iterator}
import core.text.Text

fn display_is(value: core.ascii.EscapeDefault, expected: Text): bool {
    var buffer = [0u8; 16]
    let length = {
        var writer = buffer_writer(mut buffer)
        {
            var f = formatter(mut writer, spec())
            match capture core.ascii.EscapeDefault.(Display).fmt(value, mut f) {
                success(_) => {},
                failure(_) => { return false }
            }
        }
        writer.len()
    }
    match written_text(read buffer, length) {
        present(text) => text == expected,
        none => false
    }
}

fn debug_is(value: core.ascii.EscapeDefault, expected: Text): bool {
    var buffer = [0u8; 32]
    let length = {
        var writer = buffer_writer(mut buffer)
        {
            var f = formatter(mut writer, spec())
            match capture core.ascii.EscapeDefault.(Debug).fmt(value, mut f) {
                success(_) => {},
                failure(_) => { return false }
            }
        }
        writer.len()
    }
    match written_text(read buffer, length) {
        present(text) => text == expected,
        none => false
    }
}

fn main(): i32 {
    var newline = escape_default(0x0au8)
    if !display_is(escape_default(0x0au8), "\\n") { return 11 }
    if !debug_is(escape_default(0x0au8), "EscapeDefault { .. }") { return 12 }
    if newline.len() != 2usize { return 1 }
    if newline.next_back() != present(0x6eu8) || newline.len() != 1usize { return 2 }
    if newline.next() != present(0x5cu8) { return 3 }
    if newline.next().is_present() || newline.next_back().is_present() { return 4 }

    var nul = escape_default(0u8)
    if nul.len() != 4usize { return 5 }
    if nul.next() != present(0x5cu8) { return 6 }
    if nul.next() != present(0x78u8) { return 7 }
    if nul.next() != present(0x30u8) { return 8 }
    if nul.next() != present(0x30u8) { return 9 }
    if nul.next().is_present() || nul.next().is_present() { return 10 }
    0
}
