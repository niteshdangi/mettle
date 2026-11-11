// profiles: debug release
import core.ptr.NonNull
import core.num.NonZero
import std.panic.{catch_panic, CatchResult}

fn alignment_matches<T>(address: usize, alignment: usize): bool {
    let pointer = NonNull<T>.without_provenance(NonZero<usize>.new(address).unwrap())
    let stride = core.mem.size_of<T>()
    var expected = usize.MAX
    var offset = 0usize
    while offset < alignment {
        if (address + offset * stride) % alignment == 0usize {
            expected = offset
            break
        }
        offset += 1usize
    }
    pointer.align_offset(alignment) == expected
}

fn rejects_alignment(alignment: usize): bool {
    match catch_panic(fn(): Unit {
        let _ = NonNull<u8>.dangling().align_offset(alignment)
    }) {
        CatchResult.Panicked(info) => info.code() == 101,
        CatchResult.Returned(_) => false
    }
}

fn main(): i32 {
    var address = 1usize
    while address <= 16usize {
        var alignment = 1usize
        while alignment <= 64usize {
            if !alignment_matches<u8>(address, alignment) ||
                !alignment_matches<[u8; 3]>(address, alignment) ||
                !alignment_matches<[u8; 6]>(address, alignment) ||
                !alignment_matches<u64>(address, alignment) ||
                !alignment_matches<Unit>(address, alignment) {
                return 1
            }
            alignment *= 2usize
        }
        address += 1usize
    }
    let high_bit = usize.MAX / 2usize + 1usize
    let one = NonZero<usize>.new(1usize).unwrap()
    let byte = NonNull<u8>.without_provenance(one)
    let odd_stride = NonNull<[u8; 3]>.without_provenance(one)
    if byte.align_offset(high_bit) != high_bit - 1usize ||
        odd_stride.align_offset(high_bit) != usize.MAX / 3usize {
        return 2
    }
    let aligned = NonNull<u64>.dangling()
    let misaligned = NonNull<u64>.without_provenance(one)
    if !aligned.is_aligned() || misaligned.is_aligned() { return 3 }
    if !rejects_alignment(0usize) || !rejects_alignment(3usize) ||
        !rejects_alignment(usize.MAX) {
        return 4
    }
    0
}
