// expect-error: region 4:39 borrowed source does not outlive the required region
fn owned<T: Transferable + Static>(take value: T): Unit {}
fn main(): i32 {
  let k = 4; let f = fn(): i32 { k }; owned(f)
  0
}
