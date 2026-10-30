// expect-error: name 6:5 duplicate associated item
enum Status {
    ready
}
impl Status {
    const ready: i32 = 1
}
fn main() { 0 }
