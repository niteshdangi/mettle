// Slice alignment splits, initialized-memory casts, ASCII escapes, and UTF-8 chunks.
import core.iter.Iterator
import core.mem.MaybeUninit

type DropCount {
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    let words = [0x1122u16, 0x3344u16]
    let view: read [u16] = read words
    let aligned = view.align_to<u8>()
    if aligned.0.len() != 0usize || aligned.2.len() != 0usize || aligned.1.len() != 4usize {
        return 1
    }
    let restored = aligned.1.align_to<u16>()
    if restored.0.len() != 0usize || restored.2.len() != 0usize || restored.1.len() != 2usize {
        return 2
    }
    if restored.1[0usize] != 0x1122u16 || restored.1[1usize] != 0x3344u16 { return 3 }
    let shifted: read [u8] = read aligned.1
    let odd = match shifted.subslice(1usize, shifted.len()) {
        present(part) => part,
        none => { return 4 }
    }
    let split = odd.align_to<u16>()
    if split.0.len() != 1usize || split.1.len() != 1usize || split.2.len() != 0usize { return 5 }

    var mutable = [0x1122u16, 0x3344u16]
    {
        let parts = mutable.align_to_mut<u8>()
        if parts.1.len() != 4usize { return 6 }
        let back = parts.1.align_to_mut<u16>()
        back.1[0usize] = 0x55aau16
    }
    if mutable[0usize] != 0x55aau16 || mutable[1usize] != 0x3344u16 { return 7 }

    var copied = [0u16, 0u16, 0u16]
    let source = [4u16, 5u16, 6u16]
    copied.write_copy_of_slice(source)
    if copied[0usize] != 4u16 || copied[1usize] != 5u16 || copied[2usize] != 6u16 { return 8 }
    var cloned = [1, 2]
    cloned.write_clone_of_slice([8, 9])
    if cloned[0] != 8 || cloned[1] != 9 { return 10 }

    var slots = [MaybeUninit<i32>.new(7), MaybeUninit<i32>.new(8)]
    {
        let memory: read [MaybeUninit<i32>] = read slots
        let values = unsafe { memory.assume_init_ref() }
        if values.len() != 2usize || values[0usize] != 7 || values[1usize] != 8 { return 11 }
    }
    {
        let memory: mut [MaybeUninit<i32>] = mut slots
        let values = unsafe { memory.assume_init_mut() }
        values[1usize] = 9
    }
    let taken = unsafe { slots.assume_init() }
    if taken[0usize] != 7 || taken[1usize] != 9 { return 12 }

    var drops = 0
    {
        var owned = [
            MaybeUninit<DropCount>.new(DropCount(core.ptr.from_mut(drops))),
            MaybeUninit<DropCount>.new(DropCount(core.ptr.from_mut(drops)))
        ]
        let memory: mut [MaybeUninit<DropCount>] = mut owned
        unsafe { memory.assume_init_drop() }
        if drops != 2 { return 13 }
    }
    if drops != 2 { return 14 }

    let quote = 0x27u8.escape_ascii()
    var quote_first = 0u8
    var quote_count = 0usize
    var cursor = quote
    while true {
        match cursor.next() {
            present(byte) => {
                if quote_count == 0usize { quote_first = byte }
                quote_count += 1usize
            },
            none => { break }
        }
    }
    if quote_count != 2usize || quote_first != 0x5cu8 { return 15 }
    let text = [104u8, 105u8, 0x0au8, 0u8]
    let expected = [104u8, 105u8, 0x5cu8, 0x6eu8, 0x5cu8, 0x78u8, 0x30u8, 0x30u8]
    var produced = text.escape_ascii()
    var index = 0usize
    while true {
        match produced.next() {
            present(byte) => {
                if index >= expected.len() || byte != expected[index] { return 16 }
                index += 1usize
            },
            none => { break }
        }
    }
    if index != expected.len() { return 16 }

    let mixed = [102u8, 111u8, 111u8, 0xffu8, 98u8, 97u8, 114u8]
    var chunks = mixed.utf8_chunks()
    match chunks.next() {
        present(chunk) => {
            if chunk.valid() != "foo" || chunk.invalid().len() != 1usize || chunk.invalid()[0usize] != 0xffu8 {
                return 17
            }
        },
        none => { return 17 }
    }
    match chunks.next() {
        present(chunk) => {
            if chunk.valid() != "bar" || chunk.invalid().len() != 0usize { return 18 }
        },
        none => { return 18 }
    }
    match chunks.next() { present(chunk) => { return 19 }, none => {} }

    let broken = [0xe1u8, 0x80u8, 0xffu8, 0x41u8]
    var parts = broken.utf8_chunks()
    match parts.next() {
        present(chunk) => {
            if chunk.valid().len() != 0usize || chunk.invalid().len() != 2usize { return 20 }
        },
        none => { return 20 }
    }
    match parts.next() {
        present(chunk) => {
            if chunk.invalid().len() != 1usize || chunk.invalid()[0usize] != 0xffu8 { return 21 }
        },
        none => { return 21 }
    }
    match parts.next() {
        present(chunk) => {
            if chunk.valid() != "A" || chunk.invalid().len() != 0usize { return 22 }
        },
        none => { return 22 }
    }
    let truncated = [0x66u8, 0xc2u8]
    var truncated_chunks = truncated.utf8_chunks()
    match truncated_chunks.next() {
        present(chunk) => {
            if chunk.valid() != "f" || chunk.invalid().len() != 1usize || chunk.invalid()[0usize] != 0xc2u8 {
                return 23
            }
        },
        none => { return 23 }
    }
    0
}
