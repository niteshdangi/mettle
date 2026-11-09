// expect-error: type 4:14 unsatisfied interface bound 'Static'
fn owned<T: Transferable + Static>(value: take T): Unit {}
fn main(): i32 {
  let k = 4; owned(read k)
  0
}
