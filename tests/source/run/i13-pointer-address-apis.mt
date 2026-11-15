import core.ptr

fn main(): i32 {
    var value = 12u32
    let pointer = core.ptr.from_mut(value)
    if !core.ptr.addr_eq(pointer.cast_const(), pointer.cast_const().cast<u8>()) {
        return 1
    }

    let dangling = core.ptr.dangling<u32>()
    if dangling.addr() == 0usize || !dangling.is_aligned() { return 2 }
    let dangling_mut = core.ptr.dangling_mut<u32>()
    if dangling_mut.addr() == 0usize || !dangling_mut.is_aligned() { return 3 }

    let exposed = core.ptr.with_exposed_provenance_mut<u8>(8usize)
    let without = core.ptr.without_provenance_mut<u8>(16usize)
    if exposed.addr() != 8usize || without.addr() != 16usize { return 4 }
    0
}
