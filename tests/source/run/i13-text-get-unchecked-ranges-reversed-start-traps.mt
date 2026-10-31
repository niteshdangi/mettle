// expect-exit: 101
// A range whose end precedes its start violates the unsafe contract; the
// length subtraction traps on overflow instead of manufacturing a view.
fn main(): i32 {
    var bytes = [0x61u8, 0x62u8, 0x63u8]
    var text = match core.text.from_utf8_mut(mut bytes) {
        present(value) => value,
        none => { return 1 }
    }
    let part = unsafe { text.get_unchecked_mut(2usize, 1usize) }
    part.len() as i32
}
