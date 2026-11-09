// expect-error: region 4:14 borrowed source does not outlive the required region
fn owned<T: Transferable + Static>(value: take T): Unit {}
fn main(): i32 {
  let k = 4; owned(read k)
  0
}
