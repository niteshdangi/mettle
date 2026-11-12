// profiles: debug release
// expect-error-count: 6
// expect-error-source: core/ptr.mt
// expect-error: constant 236:26 constant pointer is dangling, misaligned or out of bounds
// expect-error: constant 326:13 constant nonoverlapping copy has overlapping ranges
// expect-error: constant 276:18 constant write requires exclusive writable provenance
// expect-error: constant 251:18 constant pointer distance requires common provenance
// expect-error: constant 261:18 constant value is not fully initialized
// expect-error: constant 256:18 constant pointer distance is outside its result domain

import core.ptr.NonNull

const fn bounds(): Unit {
    var value = 7i32
    let pointer = NonNull<i32>.from_mut(mut value)
    let _ = unsafe { pointer.add(2usize) }
}

const fn overlap(): Unit {
    var values = [1i32, 2i32, 3i32]
    let pointer = NonNull<[i32; 3]>.from_mut(mut values).cast<i32>()
    unsafe { pointer.copy_to_nonoverlapping(pointer.add(1usize), 2usize) }
}

const fn readonly(): Unit {
    let value = 7i32
    let pointer = NonNull<i32>.from_ref(read value)
    unsafe { pointer.write(11i32) }
}

const fn origins(): isize {
    var first = 7i32
    var second = 11i32
    let left = NonNull<i32>.from_mut(mut first)
    let right = NonNull<i32>.from_mut(mut second)
    unsafe { left.offset_from(right) }
}

const fn validity(): bool {
    var value = false
    let pointer = NonNull<bool>.from_mut(mut value)
    unsafe {
        pointer.write_bytes(2u8, 1usize)
        pointer.`read`()
    }
}

const fn unsigned_distance(): usize {
    var values = [1i32, 2i32]
    let first = NonNull<[i32; 2]>.from_mut(mut values).cast<i32>()
    let last = unsafe { first.add(1usize) }
    unsafe { first.offset_from_unsigned(last) }
}

const BOUNDS: Unit = bounds()
const OVERLAP: Unit = overlap()
const READONLY: Unit = readonly()
const ORIGINS: isize = origins()
const VALIDITY: bool = validity()
const UNSIGNED: usize = unsigned_distance()

fn main(): i32 { 0 }
