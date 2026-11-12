
fn copy_values<T>(source: ptr<read T>, target: ptr<mut T>, count: usize) {
    unsafe { core.ptr.copy_nonoverlapping(source,target,count) }
}
fn main() {
    var values = [1u32,2u32,3u32,4u32]
    var output = [0u32,0u32,0u32,0u32]
    let pointer = core.ptr.from_mut(values).cast<u32>()
    let target = core.ptr.from_mut(output).cast<u32>()
    unsafe {
        core.ptr.`copy`(pointer,pointer.add(1),3)
        core.ptr.swap(pointer,pointer.add(3))
    }
    copy_values(pointer.cast_const(),target,4)
    let copied = output[0] == 3u32 && output[1] == 1u32 &&
                 output[2] == 2u32 && output[3] == 1u32
    output = [5u32,6u32,7u32,8u32]
    unsafe {
        core.ptr.swap_nonoverlapping(pointer,target,4)
        core.ptr.write_bytes(target,42,1)
        core.ptr.copy_nonoverlapping(pointer,target,0)
    }
    let distance = unsafe { pointer.add(3).offset_from(pointer) }
    let bytes = unsafe { pointer.add(3).byte_offset_from_unsigned(pointer) }
    if copied && output[0] == 0x2a2a2a2au32 &&
       output[1] == 1u32 && output[2] == 2u32 && output[3] == 1u32 &&
       values[0] == 5u32 && values[1] == 6u32 &&
       values[2] == 7u32 && values[3] == 8u32 &&
       distance == 3isize && bytes == 12usize { 0 } else { 1 }
}
