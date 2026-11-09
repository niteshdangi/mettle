// profiles: debug release
import core.ptr
import core.ptr.NonNull
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.convert.From
import core.hash.{Hash, Hasher, fnv1a}
import core.num.NonZero
import core.fmt
import core.fmt.Debug
import std.panic.{catch_panic, CatchResult}

fn digest<T: Hash>(read value: T): u64 {
    var hasher = fnv1a()
    value.hash(mut hasher)
    hasher.finish()
}

fn debug_pointer<T: Debug>(read value: T): bool {
    var buffer = [0u8; 80]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read buffer, written) {
        present(actual) => actual.starts_with("0x"),
        none => false
    }
}

fn write_through(mut pointer: NonNull<i32>, value: i32): Unit {
    unsafe { *pointer.as_mut() = value }
}

type DropMarker {
    count: ptr<mut i32>
    drop { unsafe { *self.count += 1i32 } }
}

fn main(): i32 {
    var value = 7i32
    let raw = core.ptr.from_mut(mut value)
    var sequence = [2i32, 4i32, 6i32]
    let start = NonNull.new(sequence.as_mut_ptr()).unwrap()
    let dangling = NonNull<i32>.dangling()
    if dangling.addr().get() != core.mem.align_of<i32>() { return 44 }
    let second = unsafe { start.add(1usize) }
    if second.as_ptr() != unsafe { start.offset(1isize).as_ptr() } { return 1 }
    if second.as_ptr() != unsafe { start.byte_add(core.mem.size_of<i32>()).as_ptr() } {
        return 2
    }
    if unsafe { second.offset_from(start) } != 1isize ||
        unsafe { second.offset_from_unsigned(start) } != 1usize { return 3 }
    if unsafe { second.byte_offset_from(start) } != core.mem.size_of<i32>() as isize ||
        unsafe { second.byte_offset_from_unsigned(start) } != core.mem.size_of<i32>() {
        return 4
    }
    if unsafe { second.sub(1usize) } != start ||
        unsafe { second.byte_sub(core.mem.size_of<i32>()) } != start { return 5 }
    let slice_pointer = NonNull.slice_from_raw_parts(start, 3usize)
    if slice_pointer.len() != 3usize || slice_pointer.is_empty() { return 6 }
    let shorter_slice_pointer = NonNull.slice_from_raw_parts(start, 2usize)
    if core.ptr.eq(
        slice_pointer.as_ptr().cast_const(),
        shorter_slice_pointer.as_ptr().cast_const()
    ) { return 46 }
    var slice_bytes = [11u8, 22u8, 33u8]
    let byte_slice = NonNull.slice_from_raw_parts(
        NonNull.new(slice_bytes.as_mut_ptr()).unwrap(),
        2usize
    )
    let next_byte_slice = unsafe { byte_slice.byte_add(1usize) }
    if next_byte_slice.addr().get() != byte_slice.addr().get() + 1usize ||
        next_byte_slice.len() != 2usize { return 54 }
    if unsafe { next_byte_slice.byte_offset_from(byte_slice) } != 1isize ||
        unsafe { next_byte_slice.byte_offset_from_unsigned(byte_slice) } != 1usize {
        return 55
    }
    if unsafe { next_byte_slice.byte_sub(1usize) } != byte_slice ||
        unsafe { byte_slice.byte_offset(1isize) } != next_byte_slice { return 56 }

    let pointer = match NonNull.new(raw) {
        present(pointer) => pointer,
        none => { return 7 }
    }
    if NonNull.new(core.ptr.null_mut<i32>()).is_present() { return 8 }
    if !core.ptr.null<i32>().is_null() { return 9 }
    if pointer.as_ptr() != raw { return 9 }
    if !core.ptr.eq(raw.cast_const(), pointer.as_ptr().cast_const()) { return 10 }
    let address = pointer.addr()
    if address.get() == 0usize { return 11 }
    if pointer.with_addr(address) != pointer { return 12 }
    let mapped = pointer.map_addr(
        fn(address: NonZero<usize>): NonZero<usize> { address }
    )
    if mapped != pointer { return 13 }
    let exposed = pointer.expose_provenance()
    if exposed.get() == 0usize { return 14 }
    let exposed_pointer = NonNull<i32>.with_exposed_provenance(exposed)
    if exposed_pointer != pointer { return 15 }
    let no_provenance = NonNull<i32>.without_provenance(address)
    if no_provenance.addr() != address { return 16 }
    let ref_pointer = NonNull.from_ref(read value)
    if ref_pointer.as_ptr().cast_const() != raw.cast_const() { return 17 }
    if !pointer.is_aligned() ||
        pointer.align_offset(core.mem.align_of<i32>() as isize) != 0usize {
        return 18
    }
    let align8_offset = pointer.align_offset(8isize)
    if align8_offset == usize.MAX ||
        (address.get() % 8usize +
            (align8_offset % 8usize) * (core.mem.size_of<i32>() % 8usize)) %
            8usize != 0usize { return 45 }
    let zero_sized = NonNull<Unit>.dangling()
    if zero_sized.align_offset(1isize) != 0usize ||
        zero_sized.align_offset(8isize) != usize.MAX { return 48 }
    let misaligned = NonNull<i32>.without_provenance(
        NonZero<usize>.new(1usize).unwrap()
    )
    if misaligned.is_aligned() || misaligned.align_offset(8isize) != usize.MAX {
        return 50
    }
    let odd_sized = NonNull<[u8; 3]>.without_provenance(
        NonZero<usize>.new(1usize).unwrap()
    )
    if odd_sized.align_offset(8isize) != 5usize { return 51 }
    match catch_panic(fn(): Unit {
        let _ = pointer.align_offset(3isize)
    }) {
        CatchResult.Panicked(info) => {
            if info.code() != 101 { return 52 }
        },
        CatchResult.Returned(_) => { return 53 }
    }

    let unchecked = unsafe { NonNull.new_unchecked(raw) }
    if unchecked.as_ptr() != raw { return 19 }
    let copied = unchecked
    if copied != unchecked || copied.cmp(read unchecked) != Ordering.Equal { return 20 }
    if !debug_pointer(read copied) { return 43 }
    match copied.partial_cmp(read unchecked) {
        present(ordering) => { if ordering != Ordering.Equal { return 21 } },
        none => { return 21 }
    }
    if digest(read copied) != digest(read unchecked) { return 22 }

    var from_value = 13i32
    let from_mut = NonNull<i32>.(From<mut i32>).from(mut from_value)
    if from_mut.as_ptr() != core.ptr.from_mut(mut from_value) { return 23 }
    let from_read = NonNull<i32>.(From<read i32>).from(read from_value)
    if from_read.as_ptr().addr() != core.ptr.from_ref(read from_value).addr() {
        return 47
    }
    let cast = from_mut.cast<u8>()
    if cast.as_ptr().addr() != from_mut.as_ptr().addr() { return 24 }
    var mut_handle = NonNull.from_mut(mut from_value)
    if unsafe { *mut_handle.as_ref() } != 13i32 { return 25 }
    write_through(mut_handle, 17i32)
    if from_value != 17i32 { return 26 }

    unsafe { core.ptr.write(raw, 9i32) }
    if unsafe { core.ptr.`read`(raw.cast_const()) } != 9i32 { return 27 }
    if unsafe { pointer.`read`() } != 9i32 { return 28 }
    if unsafe { pointer.read_unaligned() } != 9i32 { return 29 }
    if unsafe { pointer.read_volatile() } != 9i32 { return 30 }
    let replaced = unsafe { pointer.replace(10i32) }
    if replaced != 9i32 || unsafe { pointer.`read`() } != 10i32 { return 31 }
    unsafe { pointer.write(11i32) }
    if unsafe { pointer.`read`() } != 11i32 { return 32 }
    unsafe { pointer.write_unaligned(12i32) }
    if unsafe { pointer.read_unaligned() } != 12i32 { return 33 }
    unsafe { pointer.write_volatile(13i32) }
    if unsafe { pointer.read_volatile() } != 13i32 { return 34 }
    var first = 3i32
    var second_value = 8i32
    let first_pointer = NonNull.from_mut(mut first)
    let second_pointer = NonNull.from_mut(mut second_value)
    unsafe { first_pointer.swap(second_pointer) }
    if first != 8i32 || second_value != 3i32 { return 41 }
    var bytes = [0u8, 0u8, 0u8, 0u8]
    let bytes_pointer = NonNull.new(bytes.as_mut_ptr()).unwrap()
    unsafe { bytes_pointer.write_bytes(0xabu8, 4usize) }
    if bytes[0usize] != 0xabu8 || bytes[3usize] != 0xabu8 { return 42 }

    var copied_value = 0i32
    let copied_ptr = core.ptr.from_mut(mut copied_value)
    unsafe { core.ptr.`copy`(raw.cast_const(), copied_ptr, 1usize) }
    var nonoverlap_value = 0i32
    unsafe {
        core.ptr.copy_nonoverlapping(raw.cast_const(), core.ptr.from_mut(mut nonoverlap_value), 1usize)
    }
    if nonoverlap_value != 13i32 { return 35 }
    let copied_nonnull = NonNull.new(copied_ptr).unwrap()
    unsafe { copied_nonnull.copy_from(raw.cast_const(), 1usize) }
    if copied_value != 13i32 { return 36 }
    var output = 0i32
    let output_ptr = NonNull.new(core.ptr.from_mut(mut output)).unwrap()
    unsafe { copied_nonnull.copy_to(output_ptr.as_ptr(), 1usize) }
    if output != 13i32 { return 37 }
    var overlap_first = 0i32
    var overlap_second = 0i32
    let overlap_ptr = NonNull.new(core.ptr.from_mut(mut overlap_first)).unwrap()
    unsafe { overlap_ptr.copy_from_nonoverlapping(raw.cast_const(), 1usize) }
    unsafe { overlap_ptr.copy_to_nonoverlapping(core.ptr.from_mut(mut overlap_second), 1usize) }
    if overlap_first != 13i32 || overlap_second != 13i32 { return 38 }

    var global_count = 0i32
    var global_owner = core.mem.ManuallyDrop.new(
        DropMarker(core.ptr.from_mut(mut global_count))
    )
    unsafe {
        core.ptr.drop_in_place(core.ptr.from_mut(mut global_owner).cast<DropMarker>())
    }
    if global_count != 1i32 { return 39 }

    var nonnull_count = 0i32
    var nonnull_owner = core.mem.ManuallyDrop.new(
        DropMarker(core.ptr.from_mut(mut nonnull_count))
    )
    let nonnull_drop = NonNull.new(
        core.ptr.from_mut(mut nonnull_owner).cast<DropMarker>()
    ).unwrap()
    unsafe { nonnull_drop.drop_in_place() }
    if nonnull_count != 1i32 { return 40 }

    var slice_drop_count = 0i32
    var slice_owners = [
        DropMarker(core.ptr.from_mut(mut slice_drop_count)),
        DropMarker(core.ptr.from_mut(mut slice_drop_count))
    ]
    let slice_owner = NonNull.slice_from_raw_parts(
        NonNull.new(slice_owners.as_mut_ptr()).unwrap(),
        2usize
    )
    unsafe { slice_owner.drop_in_place() }
    core.mem.forget(take slice_owners)
    if slice_drop_count != 2i32 { return 58 }
    0
}
