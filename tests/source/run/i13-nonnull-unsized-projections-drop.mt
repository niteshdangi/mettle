// profiles: debug release
import core.ptr.NonNull

type Tracked {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += self.value } }
}

fn main(): i32 {
    var drops = 0i32
    let empty = NonNull.slice_from_raw_parts(NonNull<Tracked>.dangling(), 0usize)
    if !empty.is_empty() || unsafe { empty.as_ref() }.len() != 0usize {
        return 1
    }
    unsafe { empty.drop_in_place() }
    if drops != 0i32 { return 2 }

    {
        var storage = core.mem.ManuallyDrop.new([
            Tracked(core.ptr.from_mut(mut drops), 2i32),
            Tracked(core.ptr.from_mut(mut drops), 3i32)
        ])
        let data = core.ptr.from_mut(mut storage).cast<Tracked>()
        var slice = NonNull.slice_from_raw_parts(NonNull.new(data).unwrap(), 2usize)
        {
            let view = unsafe { slice.as_ref() }
            if view.len() != 2usize || view[0usize].value != 2i32 ||
                view[1usize].value != 3i32 { return 3 }
        }

        unsafe { slice.as_mut()[1usize].value = 5i32 }
        if drops != 0i32 { return 4 }
        unsafe { slice.drop_in_place() }
        if drops != 7i32 { return 5 }
    }
    if drops != 7i32 { return 6 }
    0
}
