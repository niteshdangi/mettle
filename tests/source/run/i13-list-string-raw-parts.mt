import alloc.string
import alloc.vec

type Counted {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}

fn main(): i32 {
    var drops = 0
    {
        var values = vec.new<Counted>()
        values.push(Counted(core.ptr.from_mut(drops)))
        values.push(Counted(core.ptr.from_mut(drops)))
        let raw = values.into_raw_parts()
        if drops != 0 { return 1 }
        if raw.1 != 2usize || raw.2 < raw.1 { return 2 }
        var restored = unsafe { vec.from_raw_parts<Counted>(raw.0, raw.1, raw.2) }
        if restored.len() != 2usize { return 3 }
    }
    if drops != 2 { return 4 }

    var numbers = [1, 0, 2, 0, 3]
    {
        let slice = mut numbers
        let parts = unsafe { slice.split_at_mut_unchecked(2usize) }
        if parts.0.len() != 2usize || parts.1[0usize] != 2 { return 5 }
        parts.1[0usize] = 9
    }
    if numbers[2usize] != 9 { return 6 }
    {
        let slice: read [i32] = read numbers
        let parts = unsafe { slice.split_at_unchecked(2usize) }
        if parts.0[1usize] != 0 || parts.1[0usize] != 9 { return 7 }
    }
    {
        let slice = mut numbers
        var parts = slice.rsplit_mut(fn(value: read i32): bool { value == 0 })
        match take parts.next() {
            present(part) => { if part.len() != 1usize || part[0usize] != 3 { return 8 } },
            none => { return 8 }
        }
        match take parts.next() {
            present(part) => {
                if part.len() != 1usize || part[0usize] != 9 { return 9 }
                part[0usize] = 4
            },
            none => { return 9 }
        }
    }
    if numbers[2usize] != 4 { return 10 }
    {
        let slice = mut numbers
        var parts = slice.splitn_mut(2usize, fn(value: read i32): bool { value == 0 })
        match take parts.next() {
            present(part) => { if part.len() != 1usize || part[0usize] != 1 { return 11 } },
            none => { return 11 }
        }
        match take parts.next() {
            present(part) => { if part.len() != 3usize || part[0usize] != 4 { return 12 } },
            none => { return 12 }
        }
        match take parts.next() { present(_) => { return 13 }, none => {} }
    }
    {
        let slice = mut numbers
        var parts = slice.rsplitn_mut(2usize, fn(value: read i32): bool { value == 0 })
        match take parts.next() {
            present(part) => { if part.len() != 1usize || part[0usize] != 3 { return 14 } },
            none => { return 14 }
        }
        match take parts.next() {
            present(part) => { if part.len() != 3usize || part[0usize] != 1 { return 15 } },
            none => { return 15 }
        }
    }

    var owned = string.from_text("ab")
    let raw = owned.into_raw_parts()
    if raw.1 != 2usize || raw.2 < raw.1 { return 16 }
    var back = unsafe { string.from_raw_parts(raw.0, raw.1, raw.2) }
    if back.len() != 2usize || back.as_bytes()[0usize] != 0x61u8 { return 17 }
    {
        let view = mut back
        let bytes = unsafe { view.as_bytes_mut() }
        bytes[0usize] = 0x63u8
    }
    if back.as_bytes()[0usize] != 0x63u8 || back.as_bytes()[1usize] != 0x62u8 { return 18 }
    {
        let view = mut back
        let text = view.as_mut_str()
        if text.len() != 2usize || text.as_bytes()[1usize] != 0x62u8 { return 19 }
    }
    0
}
