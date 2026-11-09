// expect-error: type 4:39 unsatisfied interface bound 'Static'
fn owned<T: Transferable + Static>(value: take T): Unit {}
fn main(): i32 {
  let k = 4; let f = fn(): i32 { k }; owned(f)
  0
}
