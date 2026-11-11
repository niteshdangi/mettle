// expect-error: feature 4:23 foreign parameter has no specified C-compatible representation
copy type Native { value: i32 }
extern "C" {
    unsafe fn consume(value: [Native; 65]): Unit;
}
fn main() { 0 }
