// profiles: debug release
import core.ptr.NonNull
import core.cmp.PartialEq

type Counted {
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1i32 } }
}

fn main(): i32 {
    var values = [1i32, 2i32, 3i32, 4i32, 5i32]
    let start = NonNull.new(values.as_mut_ptr()).unwrap()
    let second = unsafe { start.add(1usize) }
    unsafe { start.copy_to(second, 4usize) }
    if values != [1i32, 1i32, 2i32, 3i32, 4i32] { return 1 }
    unsafe { start.copy_from(second, 4usize) }
    if values != [1i32, 2i32, 3i32, 4i32, 4i32] { return 2 }
    var destination = [0i32; 5]
    let target = NonNull.new(destination.as_mut_ptr()).unwrap()
    unsafe { start.copy_to_nonoverlapping(target, 5usize) }
    if destination != values { return 3 }
    unsafe { start.write(9i32) }
    unsafe { target.copy_from_nonoverlapping(start, 5usize) }
    if destination != [9i32, 2i32, 3i32, 4i32, 4i32] { return 4 }
    let dangling = NonNull<i32>.dangling()
    unsafe {
        dangling.copy_to(dangling, 0usize)
        dangling.copy_from(dangling, 0usize)
        dangling.copy_to_nonoverlapping(dangling, 0usize)
        dangling.copy_from_nonoverlapping(dangling, 0usize)
    }
    var drops = 0i32
    var source = core.mem.ManuallyDrop.new(Counted(core.ptr.from_mut(mut drops)))
    var storage = core.mem.MaybeUninit<Counted>.uninit()
    let owner = NonNull.new(source.as_mut_ptr()).unwrap()
    let output = NonNull.new(storage.as_mut_ptr()).unwrap()
    unsafe { owner.copy_to_nonoverlapping(output, 1usize) }
    if drops != 0i32 { return 5 }
    unsafe { output.drop_in_place() }
    if drops != 1i32 { return 6 }
    0
}
