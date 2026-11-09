copy type Item { tag: u8; offset: u32; value: read i32 from static }
type Storage<T> { pointer: ptr<read T> }
type State { items: Storage<Item>; count: usize }

extend State {
    init() {
        self.items = Storage<Item>(core.ptr.null<Item>())
        self.count = 0usize
    }
}

fn main(): i32 {
    let state = State()
    state.count as i32
}
