// expect-error: ownership 9:5 live read loan

type Item<region r> { tag: u8; offset: u32; value: read i32 from r }
type State<T> { items: heap T; count: usize }

fn main(): i32 {
    var value = 1
    let state = State(heap Item(0u8, 0u32, read value), 0usize)
    value = 2
    *state.items.get().value - 1
}
