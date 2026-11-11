// expect-error: type 7:11 unsatisfied interface bound 'Transferable'
import std.thread
import alloc.rc

fn main(): i32 {
  let counted = rc.new(1)
  let h = thread.spawn(take fn(): i32 { *counted.get() })
  0
}
