// profiles: debug release
import core.mem
import core.cmp.{Ordering, PartialEq, PartialOrd}
import core.ops.{Deref, DerefMut}

type Counted {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += self.value } }
}

fn tail(mut value: core.mem.ManuallyDrop<[i32]>): usize {
    value.deref_mut()[1usize] = 9i32
    value.deref().len()
}

unsafe fn drop_tail(mut value: core.mem.ManuallyDrop<[Counted]>): Unit {
    unsafe { value.`drop`() }
}

fn cell_tail(read value: core.cell.UnsafeCell<[i32]>): usize {
    unsafe { (read *value.get()).len() }
}

fn main(): i32 {
    var drops = 0i32
    {
        var manual = core.mem.ManuallyDrop.new(
            Counted(core.ptr.from_mut(mut drops), 7i32)
        )
        if manual.deref().value != 7i32 { return 1 }
        manual.deref_mut().value = 11i32
        let value = unsafe { manual.`take`() }
        if value.value != 11i32 || drops != 0i32 { return 2 }
    }
    if drops != 11i32 { return 3 }
    var left = core.mem.ManuallyDrop.new(2i32)
    let right = core.mem.ManuallyDrop.new(5i32)
    *left.deref_mut() = 5i32
    if !left.eq(read right) { return 4 }
    match left.partial_cmp(read right) {
        present(order) => { if order != Ordering.Equal { return 5 } },
        none => { return 6 }
    }
    var array = core.mem.ManuallyDrop.new([3i32, 4i32])
    if tail(mut array) != 2usize || array.deref()[1usize] != 9i32 { return 7 }
    let cell = core.cell.UnsafeCell.new([5i32, 6i32, 7i32])
    if cell_tail(read cell) != 3usize { return 8 }
    {
        var array = core.mem.ManuallyDrop.new([
            Counted(core.ptr.from_mut(mut drops), 2i32),
            Counted(core.ptr.from_mut(mut drops), 3i32)
        ])
        if drops != 11i32 { return 9 }
        unsafe { drop_tail(mut array) }
        if drops != 16i32 { return 10 }
    }
    if drops != 16i32 { return 11 }
    {
        var empty: core.mem.ManuallyDrop<[Counted; 0]> = core.mem.ManuallyDrop.new([])
        unsafe { drop_tail(mut empty) }
    }
    if drops != 16i32 { return 12 }
    0
}
