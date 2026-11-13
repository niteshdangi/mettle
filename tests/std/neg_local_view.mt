// expect-error: region 7:11 viewed source does not outlive the required region
import std.thread

fn main(): i32 {
  let stack_slot = 5
  let borrowing = fn(): i32 { stack_slot + 1 }
  let h = thread.spawn(borrowing)
  0
}
