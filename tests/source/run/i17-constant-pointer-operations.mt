// profiles: debug release

unsafe fn shared_view<region r>(pointer: ptr<read i32>): (read i32 from r)? {
    pointer.as_ref<region r>()
}
unsafe fn shared_mut_pointer<region r>(pointer: ptr<mut i32>): (read i32 from r)? {
    pointer.as_ref<region r>()
}
unsafe fn exclusive<region r>(pointer: ptr<mut i32>): (mut i32 from r)? {
    pointer.as_mut<region r>()
}
unsafe fn shared_unchecked<region r>(pointer: ptr<read i32>): read i32 from r {
    pointer.as_ref_unchecked<region r>()
}
unsafe fn shared_mut_unchecked<region r>(pointer: ptr<mut i32>): read i32 from r {
    pointer.as_ref_unchecked<region r>()
}
unsafe fn exclusive_unchecked<region r>(pointer: ptr<mut i32>): mut i32 from r {
    pointer.as_mut_unchecked<region r>()
}

const fn compute(): i32 {
    var values = [20i32, 21i32]
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
        if *boundary.as_ref_unchecked() != 20i32 ||
           *bytes.as_ref_unchecked() != 20i32 ||
           *modular.as_ref_unchecked() != 20i32 ||
           *read_pointer.as_ref_unchecked() != 20i32 { return -1i32 }
        wrapped.replace(22i32) + *pointer.as_ref_unchecked()
    }
}

const fn array_views(): bool {
    let read_pointer = core.ptr.slice_from_raw_parts(core.ptr.null<i32>(), 7usize)
    let exclusive = core.ptr.slice_from_raw_parts_mut(core.ptr.null_mut<i32>(), 9usize)
    let shared_matches = match read_pointer.as_array<7usize>() {
        present(array) => array.is_null(),
        nil => false
    }
    let mutable_matches = match exclusive.as_mut_array<9usize>() {
        present(array) => array.is_null(),
        nil => false
    }
    let wrong_length = match read_pointer.as_array<8usize>() {
        present(_) => false,
        nil => true
    }
    shared_matches && mutable_matches && wrong_length
}

const RESULT: i32 = compute()
const ARRAY_VIEWS: bool = array_views()

fn main(): i32 {
    let empty = unsafe { core.ptr.null<i32>().as_ref() }
    let empty_mut = unsafe { core.ptr.null_mut<i32>().as_mut() }
    let nulls = match empty {
        none => match empty_mut { none => true, present(_) => false },
        present(_) => false
    }
    var value = 40i32
    unsafe { *core.ptr.from_mut(mut value).as_mut_unchecked() += 2i32 }
    if nulls && value == 42i32 && RESULT == 41i32 && ARRAY_VIEWS { 0 } else { 1 }
}
