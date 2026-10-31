type Item {
    count: ptr<mut i32>
    drop { unsafe { *self.count += 1 } }
}
type Tail<T: unsized> {
    header: i32
    values: T
}

fn main(): i32 {
    var dropped = 0
    let count = core.ptr.from_mut(dropped)
    {
        let sized: heap Tail<[Item; 2]> =
            heap Tail(7, [Item(count), Item(count)])
        let dynamic: heap Tail<[Item]> = sized
        if dynamic.get().header != 7 { return 1 }
    }
    if dropped != 2 { return 2 }

    {
        let sized: shared Tail<[Item; 2]> =
            shared Tail(9, [Item(count), Item(count)])
        let dynamic: shared Tail<[Item]> = sized
        if dynamic.get().header != 9 { return 3 }
    }
    if dropped != 4 { return 4 }
    0
}
