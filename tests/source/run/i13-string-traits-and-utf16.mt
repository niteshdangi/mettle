// profiles: debug release

import alloc.string.{String, ToString, from_utf16be, from_utf16be_lossy, from_utf16le, from_utf16le_lossy}
import alloc.vec
import core.borrow.{AsRef, AsMut, Borrow, ToOwned}
import core.clone.Clone
import core.convert.{From, TryFrom}
import core.default.Default
import core.fmt
import core.fmt.Debug
import core.hash.hash_one
import core.iter.{FromItems, ExtendItems}
import core.ops.Add
import core.option
import core.text.{FromStr, Text}

fn debug_text<T: Debug>(read value: T): String {
    var output = String("")
    var formatter = fmt.formatter(mut output, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => {}
    }
    output
}

fn byte_view_len<T: AsRef<[u8]>>(read value: T): usize {
    T.(AsRef<[u8]>).as_ref(value).len()
}

fn main(): i32 {
    let defaulted = String.(Default).default()
    if !defaulted.is_empty() { return 1 }
    let owned = String.(From<read Text from static>).from("owned")
    if owned.as_text() != "owned" { return 2 }
    if "owned".to_owned().as_text() != "owned" { return 44 }
    if String.(Borrow<Text>).borrow(owned).len() != 5usize ||
        String.(AsRef<Text>).as_ref(owned).len() != 5usize { return 3 }
    if byte_view_len(owned) != 5usize { return 45 }
    let duplicate: String =
        String.(From<read String from static>).from(read owned)
    if duplicate.as_text() != "owned" { return 46 }
    if debug_text(owned).is_empty() || owned.to_string().as_text() != "owned" { return 4 }
    if hash_one(owned) != hash_one(owned.as_text()) { return 5 }

    var mutable = String("left/right")
    let _const_ptr = mutable.as_ptr()
    let _mut_ptr = mutable.as_mut_ptr()
    match mutable.get_mut(0usize, 4usize) {
        present(view) => { if view != "left" { return 22 } },
        none => { return 23 }
    }
    {
        let view = String.(AsMut<Text>).as_mut(mut mutable)
        if view.split_at(4usize).0 != "left" { return 6 }
    }
    mutable += "!"
    if mutable.as_text() != "left/right!" { return 7 }
    match mutable.split_at_mut_checked(4usize) {
        present(parts) => {
            if parts.0 != "left" || parts.1 != "/right!" { return 28 }
        },
        none => { return 29 }
    }
    if mutable.split_at_mut_checked(99usize).is_present() { return 30 }
    match mutable.strip_circumfix("left", "!") {
        present(body) => { if body != "/right" { return 31 } },
        none => { return 32 }
    }
    match mutable.substr_range(0usize..4usize) {
        present(part) => { if part != "left" { return 33 } },
        none => { return 34 }
    }
    if unsafe { mutable.get_unchecked(0usize, 4usize) } != "left" { return 35 }
    if unsafe { mutable.get_unchecked_mut(0usize, 4usize) } != "left" { return 36 }
    unsafe {
        let bytes = mutable.as_bytes_mut()
        bytes[0usize] = 108u8
    }
    if mutable.as_text() != "left/right!" { return 37 }
    {
        var drained = mutable.drain(0usize, 4usize)
        if drained.as_str() != "left" || byte_view_len(drained) != 4usize ||
            debug_text(drained).is_empty() { return 24 }
    }

    var parts = vec.new<read Text from static>()
    parts.push("one")
    parts.push("two")
    let joined = String.(FromItems<read Text from static>).from_iter(take parts)
    if joined.as_text() != "onetwo" { return 8 }
    var extended = String("start:")
    var more = vec.new<read Text from static>()
    more.push("a")
    more.push("b")
    extended.extend(take more)
    if extended.as_text() != "start:ab" { return 9 }
    var characters = vec.new<char>()
    characters.push('c')
    characters.push('d')
    let from_characters =
        String.(FromItems<char>).from_iter(take characters)
    if from_characters.as_text() != "cd" { return 42 }
    var appended_chars = String("ab")
    var appended_items = vec.new<char>()
    appended_items.push('c')
    String.(ExtendItems<char>).extend(mut appended_chars, take appended_items)
    if appended_chars.as_text() != "abc" { return 47 }
    var boxed_parts = vec.new<alloc.boxed.Box<Text>>()
    boxed_parts.push(String("one").into_boxed_str())
    boxed_parts.push(String("two").into_boxed_str())
    let from_boxes =
        String.(FromItems<alloc.boxed.Box<Text>>).from_iter(take boxed_parts)
    if from_boxes.as_text() != "onetwo" { return 48 }
    var string_parts = vec.new<String>()
    string_parts.push(String("one"))
    string_parts.push(String("two"))
    let from_strings =
        String.(FromItems<String>).from_iter(take string_parts)
    if from_strings.as_text() != "onetwo" { return 50 }
    var string_tail = vec.new<String>()
    string_tail.push(String("c"))
    String.(ExtendItems<String>).extend(mut appended_chars, take string_tail)
    if appended_chars.as_text() != "abcc" { return 51 }
    let added =
        String("left") + "right"
    if added.as_text() != "leftright" { return 43 }

    var valid = vec.new<u8>()
    valid.push(0x6fu8)
    valid.push(0x6bu8)
    match String.(TryFrom<alloc.vec.List<u8>>).try_from(take valid) {
        success(value) => { if value.as_text() != "ok" { return 10 } },
        failure(_) => { return 11 }
    }
    var invalid = vec.new<u8>()
    invalid.push(0xffu8)
    match String.(TryFrom<alloc.vec.List<u8>>).try_from(take invalid) {
        success(_) => { return 12 },
        failure(error) => {
            if error.valid_up_to != 0usize || error.bytes.len() != 1usize { return 13 }
        }
    }

    match capture String.(FromStr).from_str("parsed") {
        success(value) => { if value.as_text() != "parsed" { return 14 } }
    }
    match capture String("17").parse<i32>() {
        success(value) => { if value != 17i32 { return 25 } },
        failure(_) => { return 26 }
    }
    match capture from_utf16be([0x6100u16]) {
        success(value) => { if value.as_text() != "a" { return 16 } },
        failure(_) => { return 17 }
    }
    match capture from_utf16le([0x0061u16]) {
        success(value) => { if value.as_text() != "a" { return 18 } },
        failure(_) => { return 19 }
    }
    match capture String.from_utf16([0x0061u16]) {
        success(value) => { if value.as_text() != "a" { return 52 } },
        failure(_) => { return 53 }
    }
    if String.from_utf16_lossy([0x0061u16]).as_text() != "a" { return 54 }
    match capture String.from_utf16be([0x6100u16]) {
        success(value) => { if value.as_text() != "a" { return 55 } },
        failure(_) => { return 56 }
    }
    match capture String.from_utf16le([0x0061u16]) {
        success(value) => { if value.as_text() != "a" { return 57 } },
        failure(_) => { return 58 }
    }
    if String.from_utf16be_lossy([0x6100u16]).as_text() != "a" { return 59 }
    if String.from_utf16le_lossy([0x0061u16]).as_text() != "a" { return 60 }
    if from_utf16be_lossy([0x00d8u16]).as_text() != "\u{fffd}" { return 20 }
    if from_utf16le_lossy([0xd800u16, 0x0061u16]).as_text() != "\u{fffd}a" { return 21 }
    var method_utf8 = vec.new<u8>()
    method_utf8.push(0x6fu8)
    method_utf8.push(0x6bu8)
    match capture String.from_utf8(take method_utf8) {
        success(value) => { if value.as_text() != "ok" { return 61 } },
        failure(_) => { return 62 }
    }
    if String.from_utf8_lossy("ok".as_bytes()).as_text() != "ok" { return 63 }
    var method_utf8_owned = vec.new<u8>()
    method_utf8_owned.push(0x6fu8)
    method_utf8_owned.push(0x6bu8)
    if String.from_utf8_lossy_owned(take method_utf8_owned).as_text() != "ok" { return 64 }
    var unchecked_utf8 = vec.new<u8>()
    unchecked_utf8.push(0x6fu8)
    unchecked_utf8.push(0x6bu8)
    let unchecked_string = unsafe { String.from_utf8_unchecked(take unchecked_utf8) }
    if unchecked_string.as_text() != "ok" { return 65 }
    let boxed: alloc.boxed.Box<Text> = String("boxed").into_boxed_str()
    if boxed.get() != "boxed" { return 38 }
    let boxed_string =
        String.(From<alloc.boxed.Box<Text>>).from(take boxed)
    if boxed_string.as_text() != "boxed" { return 41 }
    let raw = String("raw").into_raw_parts()
    let restored = unsafe { String.from_raw_parts(raw.0, raw.1, raw.2) }
    if restored.as_text() != "raw" { return 39 }
    if String.(From<char>).from('x').as_text() != "x" { return 40 }
    let leaked = String("leaked").leak()
    if leaked.len() != 6usize { return 49 }
    0
}
