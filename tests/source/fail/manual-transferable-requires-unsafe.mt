// expect-error: unsafe 3:1 manual Transferable implementation requires unsafe impl
type Raw { p: ptr<mut u8> }
impl Raw implements Transferable {}
fn main(): i32 { 0 }
