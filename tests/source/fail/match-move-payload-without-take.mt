// expect-error-count: 1
// expect-error: ownership 7:30 pattern binding 'item' moves a non-copyable payload out of a borrowed scrutinee
// expect-help: write `match take <expr>` to consume the payload
type Owned { value: i32 }
enum Value { Held(Owned) }
fn extract(value: take Value): Owned {
    match value { Value.Held(item) => item }
}
fn main() { 0 }
