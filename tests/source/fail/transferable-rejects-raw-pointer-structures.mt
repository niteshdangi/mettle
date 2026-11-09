// expect-error: type 5:3 unsatisfied interface bound 'Transferable'
type Raw { p: ptr<mut u8> }
fn send<T: Transferable>(take value: T): Unit {}
fn main(): i32 {
  send(Raw(core.ptr.null_mut<u8>()))
  0
}
