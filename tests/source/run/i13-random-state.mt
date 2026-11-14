import core.clone.Clone
import core.hash.BuildHasher
import std.collections.hash_map.RandomState

fn main(): i32 {
    let original = RandomState.new()
    let copied = original.clone()
    assert(
        original.hash_one(0x6d6574746c65u64) == copied.hash_one(0x6d6574746c65u64),
        "cloning RandomState preserves its SipHash keys"
    )
    let next = RandomState.new()
    let _hash = next.hash_one(0x6d6574746c65u64)
    0
}
