// profiles: debug release
import core.array
import core.convert.From
import core.convert.TryFrom
import core.cmp.PartialEq

type Owned {
    value: i32
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

alias ReadPair<region r> = read [i32; 2] from r
alias MutPair<region r> = mut [i32; 2] from r

fn borrowed<region r>(take values: read [i32] from r): (Outcome<ReadPair<region r>, array.TryFromSliceError>) {
    ReadPair<region r>.(TryFrom<read [i32] from r>).try_from(values)
}

fn exclusive<region r>(take values: mut [i32] from r): (Outcome<MutPair<region r>, array.TryFromSliceError>) {
    MutPair<region r>.(TryFrom<mut [i32] from r>).try_from(take values)
}

fn main(): i32 {
    var drops = 0
    let counter = core.ptr.from_mut(drops)
    {
        let pair = (Owned(4, counter), Owned(7, counter))
        let values = [Owned; 2].(From<(Owned, Owned)>).from(pair)
        if values[0usize].value != 4 || values[1usize].value != 7 { return 1 }
        let restored = (Owned, Owned).(From<[Owned; 2]>).from(values)
        if restored.0.value != 4 || restored.1.value != 7 || drops != 0 { return 2 }
    }
    if drops != 2 { return 3 }
    let singleton = [i32; 1].(From<(i32,)>).from((9i32,))
    if singleton != [9i32] { return 4 }
    let twelve = [i32; 12].(From<(i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32)>).from(
        (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
    )
    let restored = (i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32).(From<[i32; 12]>).from(twelve)
    if restored.0 != 0 || restored.11 != 11 { return 5 }
    var values = [3i32, 8i32]
    match borrowed(read values) {
        success(array) => {
            if core.ptr.from_ref(array).cast<i32>() != core.ptr.from_ref(values).cast<i32>() { return 6 }
        },
        failure(_) => { return 7 }
    }
    match take exclusive(mut values) {
        success(array) => { array[1usize] = 11 },
        failure(_) => { return 8 }
    }
    if values != [3i32, 11i32] { return 9 }
    let copied = match [i32; 2].(TryFrom<read [i32]>).try_from(read values) {
        success(array) => array,
        failure(_) => { return 10 }
    }
    values[0usize] = 20
    if copied != [3i32, 11i32] { return 11 }
    match take [i32; 2].(TryFrom<mut [i32]>).try_from(mut values) {
        success(array) => { if array != values { return 12 } },
        failure(_) => { return 13 }
    }
    let wrong = [1i32, 2i32, 3i32]
    match borrowed(read wrong) {
        success(_) => { return 14 },
        failure(_) => {}
    }
    let empty: [i32; 0] = []
    match [i32; 0].(TryFrom<read [i32]>).try_from(read empty) {
        success(array) => { if array.len() != 0usize { return 15 } },
        failure(_) => { return 16 }
    }
    let storage = core.mem.MaybeUninit<[i32; 2]>.new([5i32, 6i32])
    let slots = [core.mem.MaybeUninit<i32>; 2].(From<core.mem.MaybeUninit<[i32; 2]>>).from(storage)
    if unsafe { slots[0usize].assume_init_read() } != 5 { return 17 }
    if unsafe { slots[1usize].assume_init_read() } != 6 { return 18 }
    let uninitialized = core.mem.MaybeUninit<[i32; 2]>.uninit()
    var writable = [core.mem.MaybeUninit<i32>; 2].(From<core.mem.MaybeUninit<[i32; 2]>>).from(uninitialized)
    writable[0usize].write(21i32)
    writable[1usize].write(34i32)
    if unsafe { writable[0usize].assume_init_read() } != 21 { return 19 }
    if unsafe { writable[1usize].assume_init_read() } != 34 { return 20 }
    0
}
