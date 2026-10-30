// expect-error: type 11:14 unsatisfied interface bound 'Static'
type Plain { a: i32; b: bool }
type Raw { p: ptr<mut u8> }
type Cellular { c: core::cell::Cell<i32> }
type Blocked { a: i32 }
impl Blocked not Transferable;
fn send<T: Transferable>(value: take T): Unit {}
fn share<T: Shareable>(value: read T): Unit {}
fn owned<T: Transferable + Static>(value: take T): Unit {}
fn main(): i32 {
  let k = 4; owned(read k)
  0
}
