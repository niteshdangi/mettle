// profiles: debug release
type Item {
    value: i32
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

fn main(): i32 {
    var drops = 0usize
    let counter = core.ptr.from_mut(drops)
    var items = alloc.vec.new<Item>()
    var calls = 0
    items.resize_with(3usize, fn(): Item { calls += 1; Item(calls + 0, counter) })
    if calls != 3 || items.len() != 3usize || items[2usize].value != 3 { return 1 }
    items.resize_with(1usize, fn(): Item { panic("not called when shrinking") })
    if calls != 3 || drops != 2usize { return 2 }
    items.clear()
    if drops != 3usize { return 3 }
    0
}
