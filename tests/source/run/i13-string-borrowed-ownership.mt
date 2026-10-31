import alloc.string
import core.text.from_utf8_mut
import core.borrow.{AsRef, Borrow, ToOwned}

fn main(): i32 {
    let text = "Mettle"
    if unsafe { text.as_ptr().read() } != 0x4du8 { return 1 }
    let pieces = text.split_at(3usize)
    if pieces.0 != "Met" || pieces.1 != "tle" { return 2 }
    match text.split_at_checked(2usize) {
        present(_) => {},
        none => { return 2 }
    }
    match text.split_at_checked(text.len() + 1usize) {
        present(_) => { return 2 },
        none => {}
    }
    let owned = text.to_owned()
    if owned.as_text() != text { return 3 }
    if owned.(AsRef<core.text.Text>).as_ref() != text { return 4 }
    if owned.(Borrow<core.text.Text>).borrow() != text { return 5 }
    let another = string.from_text(text)
    if another.(Borrow<core.text.Text>).borrow() != text { return 6 }
    let boxed_text = string.from_text(text).into_boxed_str()
    let bytes = boxed_text.into_boxed_bytes()
    if bytes.get().len() != 6usize || bytes.get()[0usize] != 0x4du8 { return 7 }

    var source = [0x61u8, 0x62u8, 0x63u8]
    var mut_text = match from_utf8_mut(mut source) {
        present(value) => value,
        none => { return 8 }
    }
    unsafe { core.ptr.write(mut_text.as_mut_ptr(), 0x41u8) }
    if mut_text != "Abc" { return 9 }
    match mut_text.get_mut(1usize, 2usize) {
        present(view) => { view[0usize] = 0x42u8 },
        none => { return 10 }
    }
    if mut_text != "ABc" { return 11 }
    match mut_text.split_at_mut_checked(1usize) {
        present(parts) => { parts.1[0usize] = 0x43u8 },
        none => { return 12 }
    }
    if mut_text != "ACc" { return 13 }
    let raw_bytes = unsafe { mut_text.as_bytes_mut() }
    raw_bytes[1usize] = 0x42u8
    if mut_text != "ABc" { return 14 }
    mut_text.make_ascii_lowercase()
    if mut_text != "abc" { return 15 }
    mut_text.make_ascii_uppercase()
    if mut_text != "ABC" { return 16 }
    var mutable_string = string.from_text("abc")
    let halves = mutable_string.split_at_mut(1usize)
    halves.1.make_ascii_uppercase()
    if mutable_string.as_text() != "aBC" { return 17 }
    0
}
