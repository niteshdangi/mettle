// profiles: debug release

import core.ptr.NonNull

@align(64)
type Aligned { value: u8 }

copy type Record {
    marker: u8
    pointer: ptr<mut i32>
}

const fn offsets(): bool {
    var values = [5u32, 11u32, 29u32]
    let first = NonNull<[u32; 3]>.from_mut(mut values).cast<u32>()
    let end = unsafe { first.add(3usize) }
    let last = unsafe { end.sub(1usize).offset(-1isize) }
    let bytes = first.cast<u8>()
    let wide = NonNull<u32>.slice_from_raw_parts(first, 3usize)
    let shifted = unsafe { wide.byte_add(4usize) }
    let misaligned = unsafe { wide.byte_add(1usize) }
    if unsafe { misaligned.byte_offset_from(bytes) } != 1isize ||
        misaligned.len() != 3usize {
        return false
    }
    let back = unsafe { shifted.byte_sub(4usize).byte_offset(8isize) }
    unsafe {
        last.`read`() == 11u32 &&
            end.offset_from(first) == 3isize &&
            first.offset_from(end) == -3isize &&
            end.offset_from_unsigned(first) == 3usize &&
            back.byte_offset_from(bytes) == 8isize &&
            bytes.byte_offset_from(back) == -8isize &&
            back.byte_offset_from_unsigned(first) == 8usize &&
            shifted.len() == 3usize && !shifted.is_empty() &&
            NonNull<u32>.slice_from_raw_parts(first, 0usize).is_empty()
    }
}

const fn storage(): bool {
    var value = 7u32
    var other = 11u32
    let pointer = NonNull<u32>.from_mut(mut value)
    let second = NonNull<u32>.from_mut(mut other)
    unsafe {
        pointer.write(13u32)
        let previous = pointer.replace(17u32)
        pointer.swap(second)
        previous == 13u32 && value == 11u32 && other == 17u32
    }
}

const fn copies(): bool {
    var values = [1i32, 2i32, 3i32, 4i32]
    var destination = [0i32; 4]
    let first = NonNull<[i32; 4]>.from_mut(mut values).cast<i32>()
    let output = NonNull<[i32; 4]>.from_mut(mut destination).cast<i32>()
    unsafe {
        first.copy_to(first.add(1usize), 3usize)
        if values[1usize] != 1i32 || values[3usize] != 3i32 { return false }
        first.copy_from(first.add(1usize), 3usize)
        first.copy_to_nonoverlapping(output, 4usize)
        output.add(1usize).copy_from_nonoverlapping(first, 2usize)
    }
    destination[0usize] == 1i32 && destination[1usize] == 1i32 &&
        destination[2usize] == 2i32 && destination[3usize] == 3i32
}

const fn unaligned(): bool {
    var bytes = [0u8; 8]
    let first = NonNull<[u8; 8]>.from_mut(mut bytes).cast<u8>()
    let word = unsafe { first.byte_add(1usize) }.cast<u32>()
    unsafe {
        word.write_unaligned(0x12345678u32)
        if word.read_unaligned() != 0x12345678u32 { return false }
        first.write_bytes(0xabu8, 8usize)
    }
    bytes[0usize] == 0xabu8 && bytes[7usize] == 0xabu8
}

const fn aggregate(): bool {
    var number = 53i32
    let record = Record(7u8, core.ptr.from_mut(mut number))
    var bytes = [0u8; 32]
    let first = NonNull<[u8; 32]>.from_mut(mut bytes).cast<u8>()
    let pointer = unsafe { first.byte_add(1usize) }.cast<Record>()
    unsafe {
        pointer.write_unaligned(record)
        let restored = pointer.read_unaligned()
        *restored.pointer = 59i32
        restored.marker == 7u8 && number == 59i32
    }
}

const fn empty(): bool {
    let pointer = NonNull<Unit>.dangling()
    let address = unsafe { core.num.NonZero<usize>.new_unchecked(1usize) }
    let same = NonNull<Unit>.without_provenance(address)
    unsafe {
        pointer.write(())
        pointer.copy_to_nonoverlapping(same, 100usize)
        pointer.`read`()
    }
    pointer.as_ptr() == same.as_ptr()
}

const fn provenance(): i32 {
    var number = 43i32
    var source = core.ptr.from_mut(mut number)
    var destination = core.ptr.null_mut<i32>()
    let from = NonNull<ptr<mut i32>>.from_mut(mut source).cast<u8>()
    let to = NonNull<ptr<mut i32>>.from_mut(mut destination).cast<u8>()
    unsafe {
        from.copy_to_nonoverlapping(to, core.mem.size_of<ptr<mut i32>>())
        *destination = 47i32
    }
    number
}

const fn raw_validity(): bool {
    var source = false
    var destination = false
    let from = NonNull<bool>.from_mut(mut source)
    let to = NonNull<bool>.from_mut(mut destination)
    unsafe {
        from.write_bytes(2u8, 1usize)
        from.copy_to_nonoverlapping(to, 1usize)
        to.write_bytes(1u8, 1usize)
        from.write_bytes(0u8, 1usize)
    }
    !source && destination
}

const fn constructors(): bool {
    let aligned = NonNull<Aligned>.dangling()
    let address = NonNull<Aligned>.without_provenance(
        unsafe { core.num.NonZero<usize>.new_unchecked(128usize) }
    )
    aligned.as_ptr() == core.ptr.without_provenance<Aligned>(64usize).cast_mut() &&
        address.as_ptr() == core.ptr.without_provenance<Aligned>(128usize).cast_mut()
}

const OFFSETS: bool = offsets()
const STORAGE: bool = storage()
const COPIES: bool = copies()
const UNALIGNED: bool = unaligned()
const AGGREGATE: bool = aggregate()
const EMPTY: bool = empty()
const PROVENANCE: i32 = provenance()
const VALIDITY: bool = raw_validity()
const CONSTRUCTORS: bool = constructors()

fn main(): i32 {
    if !OFFSETS { return 1 }
    if !STORAGE { return 2 }
    if !COPIES { return 3 }
    if !UNALIGNED { return 4 }
    if !EMPTY { return 5 }
    if PROVENANCE != 47i32 { return 6 }
    if !VALIDITY { return 7 }
    if !CONSTRUCTORS { return 8 }
    if !AGGREGATE { return 9 }
    0
}
