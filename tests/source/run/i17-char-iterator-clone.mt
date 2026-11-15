// profiles: debug release
import core.char
import core.clone.Clone
import core.iter.Iterator

type Units { position: usize }
extend Units implements Clone {
    fn clone(): Units { Units(self.position) }
}
extend Units implements Iterator {
    type Item = u16
    mut fn next(): u16? {
        if self.position >= 3usize { return none }
        let value = [0xd800u16, 0x41u16, 0x42u16][self.position]
        self.position += 1usize
        present(value)
    }
}

fn main(): i32 {
    var escape = '\n'.escape_default()
    if escape.next() != present('\\') { return 1 }
    var escape_clone = escape.clone()
    if escape_clone.next() != present('n') || escape_clone.next().is_present() { return 2 }
    if escape.next() != present('n') || escape.next().is_present() { return 3 }

    var mapping = '\u{df}'.to_uppercase()
    if mapping.next() != present('S') { return 4 }
    var mapping_clone = mapping.clone()
    if mapping_clone.next() != present('S') || mapping_clone.next().is_present() { return 5 }
    if mapping.next() != present('S') || mapping.next().is_present() { return 6 }

    var decoder = char.decode_utf16(Units(0usize))
    match decoder.next() {
        present(failure(error)) => if error.unpaired_surrogate() != 0xd800u16 { return 7 },
        _ => { return 8 }
    }
    var decoder_clone = decoder.clone()
    match decoder_clone.next() {
        present(success('A')) => {},
        _ => { return 9 }
    }
    match decoder_clone.next() {
        present(success('B')) => {},
        _ => { return 10 }
    }
    if decoder_clone.next().is_present() { return 11 }
    match decoder.next() {
        present(success('A')) => {},
        _ => { return 12 }
    }
    match decoder.next() {
        present(success('B')) => {},
        _ => { return 13 }
    }
    if decoder.next().is_present() { return 14 }
    0
}
