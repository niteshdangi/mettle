import alloc.boxed

fn main(): i32 {
    let text = boxed.copy_text("abc")
    let pointer = text.get().as_ptr()
    if unsafe { *pointer } != 97u8 { return 1 }
    var editable = boxed.copy_text("xyz")
    let write_pointer = editable.get_mut().as_mut_ptr()
    unsafe { *write_pointer = 65u8 }
    if editable.get() != "Ayz" { return 2 }
    let bytes = editable.into_heap_bytes()
    if bytes.get().len() != 3usize || bytes.get()[0usize] != 65u8 { return 3 }
    let owned = boxed.copy_text("hi").into_string()
    if owned.as_text() != "hi" { return 4 }
    0
}
