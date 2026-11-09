import core.cmp.{Ord, Ordering, PartialOrd}
import core.hash
import core.hash.{Hash, Hasher}

// Records the byte stream so tuple Hash field order is observable.
type RecordingHasher { bytes: [u8; 8]; length: usize }
extend RecordingHasher implements Hasher {
    mut fn write(read bytes: [u8]): Unit {
        var index = 0usize
        while index < bytes.len() && self.length < 8usize {
            self.bytes[self.length] = bytes[index]
            self.length += 1usize
            index += 1usize
        }
    }

    fn finish(): u64 { self.length as u64 }
}

fn ordered_and_hashed<T: Ord + Hash>(
    read left: T, read equal: T, read later: T
): bool {
    if left != equal || left.cmp(read later) != Ordering.Less { return false }
    match left.partial_cmp(read later) {
        present(order) => if !order.is_lt() { return false },
        none => { return false }
    }
    hash.hash_one(left) == hash.hash_one(equal)
}

fn main(): i32 {
    let unit = ()
    let unit_again = ()
    if unit != unit_again || unit.cmp(read unit_again) != Ordering.Equal { return 1 }
    var unit_hash = RecordingHasher([0u8; 8], 0usize)
    unit.hash(mut unit_hash)
    if unit_hash.length != 0usize { return 2 }

    if !ordered_and_hashed(
        (1i32,),
        (1i32,),
        (2i32,)
    ) { return 3 }
    if !ordered_and_hashed(
        (1i32, 2i32),
        (1i32, 2i32),
        (1i32, 3i32)
    ) { return 4 }
    if !ordered_and_hashed(
        (1i32, 2i32, 3i32),
        (1i32, 2i32, 3i32),
        (1i32, 2i32, 4i32)
    ) { return 5 }
    if !ordered_and_hashed(
        (1i32, 2i32, 3i32, 4i32),
        (1i32, 2i32, 3i32, 4i32),
        (1i32, 2i32, 3i32, 5i32)
    ) { return 6 }
    if !ordered_and_hashed(
        (1i32, 2i32, 3i32, 4i32, 5i32),
        (1i32, 2i32, 3i32, 4i32, 5i32),
        (1i32, 2i32, 3i32, 4i32, 6i32)
    ) { return 7 }
    if !ordered_and_hashed(
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 7i32)
    ) { return 8 }
    if !ordered_and_hashed(
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 8i32)
    ) { return 9 }
    if !ordered_and_hashed(
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 9i32)
    ) { return 10 }
    if !ordered_and_hashed(
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 10i32)
    ) { return 11 }
    if !ordered_and_hashed(
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32, 10i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32, 10i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32, 11i32)
    ) { return 12 }
    if !ordered_and_hashed(
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32, 10i32, 11i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32, 10i32, 11i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32, 10i32, 12i32)
    ) { return 13 }
    if !ordered_and_hashed(
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32, 10i32, 11i32, 12i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32, 10i32, 11i32, 12i32),
        (1i32, 2i32, 3i32, 4i32, 5i32, 6i32, 7i32, 8i32, 9i32, 10i32, 11i32, 13i32)
    ) { return 14 }

    let three = (1i32, 2i32, 3i32)
    let three_later = (1i32, 3i32, 0i32)
    if !(three < three_later) || three.cmp(read three_later) != Ordering.Less { return 15 }

    let nan = f64.from_bits(0x7ff8000000000042u64)
    let early_difference = (1i32, nan, 3i32)
    let later_nan = (1i32, nan, 3i32)
    let later_finite = (1i32, 0.0f64, 3i32)
    match early_difference.partial_cmp(read (2i32, 0.0f64, 0i32)) {
        present(order) => { if order != Ordering.Less { return 16 } },
        none => { return 17 }
    }
    match later_nan.partial_cmp(read later_finite) {
        none => {},
        present(order) => { return 18 }
    }

    var recording = RecordingHasher([0u8; 8], 0usize)
    (0x12u8, 0x3456u16, 0x789abcdeu32).hash(mut recording)
    if recording.length != 7usize ||
       recording.bytes[0usize] != 0x12u8 ||
       recording.bytes[1usize] != 0x56u8 ||
       recording.bytes[2usize] != 0x34u8 ||
       recording.bytes[3usize] != 0xdeu8 ||
       recording.bytes[4usize] != 0xbcu8 ||
       recording.bytes[5usize] != 0x9au8 ||
       recording.bytes[6usize] != 0x78u8 {
        return 19
    }
    0
}
