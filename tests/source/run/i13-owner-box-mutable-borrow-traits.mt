import alloc.boxed
import core.borrow.{AsMut, BorrowMut}

type Payload {
    value: i32
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

fn set_through_as_mut<T: AsMut<Payload>>(mut owner: T, value: i32): Unit {
    owner.as_mut().value = value
}

fn add_through_borrow_mut<T: BorrowMut<Payload>>(mut owner: T, value: i32): Unit {
    owner.borrow_mut().value += value
}

fn main(): i32 {
    var drops = 0
    {
        var owner = boxed.new(
            Payload(10, core.ptr.from_mut(drops))
        )
        set_through_as_mut(mut owner, 23)
        if owner.get().value != 23 { return 1 }
        add_through_borrow_mut(mut owner, 19)
        if owner.get().value != 42 { return 2 }
    }
    if drops != 1 { return 3 }
    0
}
