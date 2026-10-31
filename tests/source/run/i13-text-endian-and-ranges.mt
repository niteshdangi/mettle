import alloc.string
import alloc.vec

fn main(): i32 {
    match capture string.from_utf16be([0x00u8, 0x61u8, 0x00u8, 0x62u8]) {
        success(text) => { if text.as_text() != "ab" { return 1 } },
        failure(_) => { return 1 }
    }
    match capture string.from_utf16le([0x61u8, 0x00u8, 0x62u8, 0x00u8]) {
        success(text) => { if text.as_text() != "ab" { return 2 } },
        failure(_) => { return 2 }
    }
    match capture string.from_utf16be([0x00u8]) {
        success(_) => { return 3 },
        failure(error) => { if error.index != 0usize { return 3 } }
    }
    match capture string.from_utf16le([0xd8u8, 0x00u8]) {
        success(_) => { return 4 },
        failure(error) => { if error.index != 0usize || error.surrogate != 0xd800u16 { return 4 } }
    }
    let lossy = string.from_utf16le_lossy([0x61u8, 0x00u8, 0xffu8])
    if lossy.len() != 4usize || lossy.as_bytes()[0usize] != 0x61u8 ||
        lossy.as_bytes()[1usize] != 0xefu8 {
        return 5
    }
    let big_lossy = string.from_utf16be_lossy([0xd8u8, 0x00u8])
    if big_lossy.as_text() != "�" { return 6 }

    var owned_bytes = vec.new<u8>()
    owned_bytes.push(0x61u8)
    owned_bytes.push(0x62u8)
    let kept = string.from_utf8_lossy_owned(take owned_bytes)
    if kept.as_text() != "ab" { return 7 }
    var broken = vec.new<u8>()
    broken.push(0x61u8)
    broken.push(0xffu8)
    let repaired = string.from_utf8_lossy_owned(take broken)
    if repaired.len() != 4usize || repaired.as_bytes()[0usize] != 0x61u8 { return 8 }

    let boxed = string.from_text("hi").into_boxed_str()
    if boxed.get().len() != 2usize || boxed.get().as_bytes()[1usize] != 0x69u8 { return 9 }

    let wrapped = "[[body]]"
    match wrapped.strip_circumfix("[[", "]]") {
        present(body) => { if body != "body" { return 10 } },
        none => { return 10 }
    }
    match "xbodyx".strip_circumfix('x', 'x') {
        present(body) => { if body != "body" { return 11 } },
        none => { return 11 }
    }
    match "[[body]]".strip_circumfix("[[", ">>") {
        present(_) => { return 12 },
        none => {}
    }
    let source = "hello"
    match source.get(1usize, 4usize) {
        present(part) => {
            match source.substr_range(part) {
                present(range) => { if range.start != 1usize || range.end != 4usize { return 13 } },
                none => { return 13 }
            }
        },
        none => { return 13 }
    }
    let other = "hello"
    match source.substr_range(other) { present(_) => { return 14 }, none => {} }

    var values = [10, 20, 30, 40]
    let slice: read [i32] = read values
    match slice.get(2usize) {
        present(element) => {
            match slice.element_offset(read *element) {
                present(index) => { if index != 2usize { return 15 } },
                none => { return 15 }
            }
        },
        none => { return 15 }
    }
    var outside = 20
    match slice.element_offset(read outside) { present(_) => { return 16 }, none => {} }
    match slice.subslice(1usize, 3usize) {
        present(part) => {
            match slice.subslice_range(part) {
                present(range) => { if range.start != 1usize || range.end != 3usize { return 17 } },
                none => { return 17 }
            }
            match part.strip_circumfix([20], [30]) {
                present(middle) => { if !middle.is_empty() { return 18 } },
                none => { return 18 }
            }
        },
        none => { return 17 }
    }
    0
}
