// expect-error-count: 1
// expect-error: ownership 9:17 pattern binding 'item' moves a non-copyable payload out of a borrowed scrutinee
type Owner<region r> { value: read i32 from r }
fn produce<region r>(value: read i32 from r): Owner<region r>? { present(Owner(value)) }
fn consume<region r>(value: take Owner<region r>) {}
fn main() {
    let value = 42
    match produce(read value) {
        present(item) => consume(item),
        none => ()
    }
    0
}
