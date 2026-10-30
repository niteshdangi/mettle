// expect-error-count: 1
// expect-error: ownership 6:30 pattern binding 'item' moves a non-copyable payload out of a borrowed scrutinee
type Owned { value: i32 }
enum Value { Held(Owned) }
fn extract(value: take Value): Owned {
    match value { Value.Held(item) => item }
}
fn main() { 0 }
