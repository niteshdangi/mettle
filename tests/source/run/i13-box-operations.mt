// profiles: debug release
import alloc.boxed
import alloc.boxed.Box
import alloc.vec
import core.clone.Clone
import core.cmp.PartialEq
import core.convert.From
import core.default.Default
import core.iter.{ BidirectionalIterator, ExactSizeIterator, Iterator }

type Counted {
    value: i32
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

fn main(): i32 {
    // Construction, element access and mutation through get / get_mut.
    var owner = boxed.new(3)
    if *owner.get() != 3 { return 1 }
    *owner.get_mut() = 4
    if *owner.get() != 4 { return 2 }
    let raw_owner = owner.as_mut_ptr()
    unsafe { core.ptr.write(raw_owner, 5) }
    if *owner.get() != 5 { return 3 }
    if unsafe { *owner.as_ptr() } != 5 { return 4 }

    // Clone copies the payload into a fresh allocation.
    var copied = owner.clone()
    *copied.get_mut() = 6
    if *owner.get() != 5 || *copied.get() != 6 { return 5 }

    // Equality and ordering compare the payloads.
    let small = boxed.new(1)
    let large = boxed.new(2)
    if !(small == boxed.new(1)) || small == large { return 6 }
    if !(small < large) || large < small { return 7 }

    // Default and From<T> construct a boxed payload.
    let default_box = Box<i32>.(Default).default()
    if *default_box.get() != 0 { return 8 }
    let from_value = Box<i32>.(From<i32>).from(7)
    if *from_value.get() != 7 { return 9 }

    // into_inner moves the payload out and frees the box.
    let unwrapped = boxed.new(11).into_inner()
    if unwrapped != 11 { return 10 }

    // into_raw / from_raw_in round-trip ownership through a raw pointer.
    var round = boxed.new(20)
    let (raw_round, round_alloc) = round.into_raw()
    unsafe { *raw_round += 1 }
    let restored = unsafe { boxed.from_raw_in(raw_round, round_alloc) }
    if *restored.get() != 21 { return 11 }

    // leak hands out a pointer that from_raw can reclaim.
    let leaked = boxed.new(30).leak()
    unsafe { *leaked = 31 }
    let reclaimed = unsafe { boxed.from_raw(leaked) }
    if *reclaimed.get() != 31 { return 12 }

    // Pinned boxes deref to the payload and allow mutation when Unpin.
    var fixed_box = boxed.`pin`(40)
    if *fixed_box.get_ref() != 40 { return 13 }
    *fixed_box.get_mut() = 41
    if *fixed_box.get_ref() != 41 { return 14 }

    // Uninitialised and zeroed boxes become initialised before use.
    let written = boxed.new_uninit<i32>().write(50)
    if *written.get() != 50 { return 15 }
    let zeroed = unsafe { boxed.new_zeroed<i32>().assume_init() }
    if *zeroed.get() != 0 { return 16 }
    let slice_zeroed = unsafe { boxed.new_zeroed_slice<i32>(3usize).assume_init() }
    if slice_zeroed.get().len() != 3usize || slice_zeroed.get()[2usize] != 0 { return 17 }
    let slice_uninit = boxed.new_uninit_slice<i32>(2usize)
    if slice_uninit.get().len() != 2usize { return 18 }

    // Box<[T]> holds an owned slice and reports its length and contents.
    let vector = vec.new<i32>()
    var source = vector
    source.push(7)
    source.push(8)
    let slice_box = source.into_boxed_slice()
    if slice_box.get().len() != 2usize || slice_box.get()[1usize] != 8 { return 19 }
    let empty_slice = Box<[i32]>.(Default).default()
    if empty_slice.get().len() != 0usize { return 20 }

    // Box<I> forwards Iterator, DoubleEnded and ExactSize to the boxed iterator.
    let items = [1, 2, 3]
    var forwarded = boxed.new(items.iter())
    if forwarded.len() != 3usize { return 21 }
    match take forwarded.next_back() {
        present(value) => { if *value != 3 { return 22 } },
        none => { return 22 }
    }
    match take forwarded.next() {
        present(value) => { if *value != 1 { return 23 } },
        none => { return 23 }
    }
    if forwarded.len() != 1usize { return 24 }

    // Dropping a box drops its payload exactly once.
    var drops = 0usize
    {
        let _counted = boxed.new(Counted(1, core.ptr.from_mut(drops)))
    }
    if drops != 1usize { return 25 }
    {
        let moved = boxed.new(Counted(2, core.ptr.from_mut(drops)))
        let _taken = moved.into_inner()
    }
    if drops != 2usize { return 26 }
    0
}
