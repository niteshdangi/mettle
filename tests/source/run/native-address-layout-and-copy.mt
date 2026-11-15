// profiles: debug release

@layout(C)
type Inner { tag: u8; value: i32 }
@layout(C)
type Outer { tag: u8; inner: Inner }

const OFFSET: usize = core.mem.offset_of!(Outer, inner.value)
const fn copied(): u32 {
    let source = 1234u64
    unsafe { core.mem.transmute_copy<u32>(read source) }
}
const COPIED: u32 = copied()

const fn raw_components(): bool {
    let read_pointer = core.ptr.slice_from_raw_parts(core.ptr.null<i32>(), 7usize)
    let exclusive = core.ptr.slice_from_raw_parts_mut(core.ptr.null_mut<i32>(), 9usize)
    let read_matches = match read_pointer.as_array<7usize>() {
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
    read_pointer.is_null() && exclusive.is_null() &&
        read_matches && mutable_matches && wrong_length
}
const RAW_COMPONENTS: bool = raw_components()

fn answer(): i32 { 42 }
fn main(): i32 {
    if OFFSET != 8usize || COPIED != 1234u32 || !RAW_COMPONENTS { return 1 }
    var storage: core.mem.MaybeUninit<Outer> = core.mem.MaybeUninit.uninit()
    let base = storage.as_mut_ptr()
    let address = core.ptr.addr_of_mut!((*base).inner.value)
    unsafe { *address = 42 }
    let read_pointer = core.ptr.addr_of!((*base).inner.value)
    if unsafe { *read_pointer } != 42 { return 2 }
    if read_pointer.addr() - base.addr() != OFFSET { return 3 }
    let first: fn(): i32 = answer
    let second: fn(): i32 = answer
    if !core.ptr.fn_addr_eq(first, second) { return 4 }
    let bytes = [42u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]
    if unsafe { core.mem.transmute_copy<u64>(read bytes) } != 42u64 { return 5 }
    if bytes[0] != 42u8 { return 6 }
    var value = 41i32
    {
        let cell = core.cell.UnsafeCell.from_mut(mut value)
        let pointer = core.ptr.from_ref(read *cell)
        let payload = core.cell.UnsafeCell.raw_get(pointer)
        if payload.addr() != pointer.addr() { return 7 }
        unsafe { *payload = 42 }
        if *cell.get_mut() != 42 { return 8 }
    }
    if value != 42 { return 9 }
    0
}
