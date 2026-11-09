// expect-error: type 6:3 unsatisfied interface bound 'Transferable'
type Blocked { a: i32 }
extend Blocked not Transferable
fn send<T: Transferable>(value: take T): Unit {}
fn main(): i32 {
  send(Blocked(1))
  0
}
