import alloc.string
import alloc.vec
import core.convert.{From, TryFrom}
import core.from_str.FromStr

fn main(): i32 {
    if char.(From<u8>).`from`(0x41u8) != 'A' { return 1 }
    if u32.(From<char>).`from`('\u{e9}') != 0xe9u32 { return 2 }
    if u64.(From<char>).`from`('\u{10ffff}') != 0x10ffffu64 { return 3 }
    match capture char.(TryFrom<u32>).try_from(0x1f980u32) {
        success(value) => { if value != '🦀' { return 4 } },
        failure(_) => { return 4 }
    }
    match capture char.(TryFrom<u32>).try_from(0xd800u32) {
        success(_) => { return 5 },
        failure(_) => {}
    }
    match capture u8.(TryFrom<char>).try_from('z') {
        success(value) => { if value != 0x7au8 { return 6 } },
        failure(_) => { return 6 }
    }
    match capture u8.(TryFrom<char>).try_from('\u{100}') {
        success(_) => { return 7 },
        failure(_) => {}
    }

    var bytes = vec.new<u8>()
    bytes.push(104u8)
    bytes.push(105u8)
    match capture string.String.(TryFrom<vec.List<u8>>).try_from(bytes) {
        success(text) => { if text.as_text() != "hi" { return 8 } },
        failure(_) => { return 8 }
    }
    var invalid = vec.new<u8>()
    invalid.push(0xffu8)
    match capture string.String.(TryFrom<vec.List<u8>>).try_from(invalid) {
        success(_) => { return 9 },
        failure(error) => { if error.valid_up_to != 0usize { return 9 } }
    }

    var text = string.from_text("h\u{e9}llo")
    match capture "x".parse_as<string.String>() {
        success(value) => { if value.as_text() != "x" { return 10 } },
        failure(_) => { return 10 }
    }
    {
        let drained = text.drain(0usize, 1usize)
        if drained.as_str() != "h" { return 11 }
    }
    0
}
