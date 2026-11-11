// profiles: debug release
import core.ptr.NonNull
import core.cmp.PartialEq

fn main(): i32 {
    var words = [11u32, 22u32, 33u32]
    let start = NonNull.new(words.as_mut_ptr()).unwrap()
    let bytes = start.cast<u8>()
    let end = unsafe { start.add(3usize) }
    let extent = core.mem.size_of<u32>() * 3usize
    if unsafe { end.byte_offset_from(bytes) } != extent as isize ||
        unsafe { end.byte_offset_from_unsigned(bytes) } != extent {
        return 1
    }
    if unsafe { bytes.byte_offset_from(end) } != -(extent as isize) {
        return 2
    }
    let slice = NonNull.slice_from_raw_parts(start, 3usize)
    let shifted = unsafe { slice.byte_add(core.mem.size_of<u32>()) }
    if shifted.len() != 3usize || shifted.is_empty() { return 3 }
    if unsafe { shifted.byte_offset_from(bytes) } != core.mem.size_of<u32>() as isize ||
        unsafe { shifted.byte_offset_from_unsigned(start) } != core.mem.size_of<u32>() {
        return 4
    }
    if unsafe { shifted.byte_sub(core.mem.size_of<u32>()) } != slice ||
        unsafe { shifted.byte_offset(-(core.mem.size_of<u32>() as isize)) } != slice {
        return 5
    }
    let same_data = NonNull.slice_from_raw_parts(bytes, 0usize)
    if !same_data.is_empty() ||
        unsafe { same_data.byte_offset_from(slice) } != 0isize ||
        unsafe { slice.byte_offset_from_unsigned(same_data) } != 0usize {
        return 6
    }
    if unsafe { end.offset_from(start) } != 3isize ||
        unsafe { end.offset_from_unsigned(start) } != 3usize ||
        unsafe { end.sub(3usize) } != start ||
        unsafe { end.offset(-3isize) } != start {
        return 7
    }
    0
}
