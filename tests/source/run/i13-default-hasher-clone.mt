// profiles: debug release
import alloc.hash_map.DefaultHasher
import core.clone.Clone
import core.hash.{Hasher, sip_with_rounds}

fn main(): i32 {
    let prefix: [u8; 3] = [1u8, 2u8, 3u8]
    let suffix: [u8; 5] = [4u8, 5u8, 6u8, 7u8, 8u8]

    var sip = sip_with_rounds(11u64, 23u64, 2u32, 4u32)
    sip.write(read prefix)
    var sip_copy = sip.clone()
    sip.write(read suffix)
    sip_copy.write(read suffix)
    if sip.finish() != sip_copy.finish() { return 1 }

    var default_hasher = DefaultHasher.new()
    default_hasher.write(read prefix)
    var default_copy = default_hasher.clone()
    default_hasher.write(read suffix)
    default_copy.write(read suffix)
    if default_hasher.finish() != default_copy.finish() { return 2 }
    0
}
