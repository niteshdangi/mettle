// profiles: debug release

type Borrowed<region r> { value: read i32 from r }
extend<region r> Borrowed<region r> {
    fn get(): i32 { *self.value }
}
unsafe fn read_erased<region r>(pointer: ptr<read u8>): i32 {
    let value = read *pointer.cast<Borrowed<region r>>()
    value.get()
}
fn raw_layout<T: unsized>(pointer: ptr<read T>): (usize, usize) {
    unsafe {
        (core.mem.size_of_val_raw<T>(pointer),
         core.mem.align_of_val_raw<T>(pointer))
    }
}
unsafe fn pack_uninit<T, const N: usize>(
    take value: [core.mem.MaybeUninit<T>; N]
): core.mem.MaybeUninit<[T; N]> {
    core.mem.transmute<core.mem.MaybeUninit<[T; N]>>(value)
}

unsafe fn shared_view<region r>(pointer: ptr<read i32>): (read i32 from r)? {
    pointer.as_ref<region r>()
}

unsafe fn exclusive<region r>(pointer: ptr<mut i32>): (mut i32 from r)? {
    pointer.as_mut<region r>()
}

unsafe fn shared_unchecked<region r>(
    pointer: ptr<read i32>
): read i32 from r {
    pointer.as_ref_unchecked<region r>()
}

unsafe fn exclusive_unchecked<region r>(
    pointer: ptr<mut i32>
): mut i32 from r {
    pointer.as_mut_unchecked<region r>()
}

const fn compute(): i32 {
    var values = [20i32, 21]
    let pointer = core.ptr.from_mut(mut values).cast<i32>()
    let wrapped = pointer.wrapping_sub(1usize).wrapping_add(2usize)
    unsafe {
        let boundary = pointer.wrapping_add(2usize).wrapping_offset(-2isize)
        let bytes = (pointer.wrapping_byte_offset(-1isize).wrapping_byte_add(1usize)
            .wrapping_byte_sub(1usize).wrapping_byte_add(1usize))
        let readonly = pointer as ptr<read i32>
        let read_pointer = (readonly.wrapping_add(1usize).wrapping_sub(1usize)
            .wrapping_offset(0isize).wrapping_byte_add(1usize)
            .wrapping_byte_sub(1usize).wrapping_byte_offset(0isize))
        let modular = pointer.wrapping_byte_add(usize.MAX).wrapping_byte_add(1usize)
        if *boundary.as_ref_unchecked() != 20 ||
           *bytes.as_ref_unchecked() != 20 ||
           *modular.as_ref_unchecked() != 20 ||
           *read_pointer.as_ref_unchecked() != 20 { return -1 }
        let previous = wrapped.replace(22)
        previous + *pointer.as_ref_unchecked()
    }
}

const RESULT: i32 = compute()

const fn initialize_storage(): i32 {
    let empty = core.mem.MaybeUninit<i32>.uninit()
    var storage = empty
    let pointer = storage.as_mut_ptr()
    unsafe {
        pointer.write(5i32)
        let previous = pointer.replace(7i32)
        previous + storage.assume_init()
    }
}

const INITIALIZED_STORAGE: i32 = initialize_storage()

fn main(): i32 {
    let empty = unsafe { core.ptr.null<i32>().as_ref() }
    let empty_mut = unsafe { core.ptr.null_mut<i32>().as_mut() }
    let nulls = match empty {
        none => match empty_mut { none => true, present(_) => false },
        present(_) => false
    }
    var value = 40i32
    let pointer = core.ptr.from_mut(mut value)
    unsafe { *pointer.as_mut_unchecked() += 2 }
    let borrowed = Borrowed(read value)
    let erased = core.ptr.from_ref(read borrowed).cast<u8>()
    let layout = raw_layout(core.ptr.null<i32>())
    let bytes = [1u8, 2u8]
    let slice: read [u8] = read bytes
    let slice_layout = raw_layout(core.ptr.from_ref(slice))
    if nulls && RESULT == 41 && INITIALIZED_STORAGE == 12 &&
       layout == (4usize, 4usize) &&
       slice_layout == (2usize, 1usize) &&
       unsafe { read_erased(erased) } == 42 { 0 } else { 1 }
}
