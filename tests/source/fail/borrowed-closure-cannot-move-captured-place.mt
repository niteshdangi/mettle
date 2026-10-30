// expect-error: ownership 7:39 requires a take closure

type Item { value: i32 }
fn consume(item: take Item): i32 { item.value }
fn main(): i32 {
    let item = Item(42)
    let closure = fn(): i32 { consume(item) }
    closure()
}
