// expect-error: type
import std.thread;
import alloc.arc;

fn main(): i32 {
  let cell = arc.new(core.cell.Cell.new(1))
  let other = cell.retain()
  let h = thread.spawn(take fn(): i32 { other.get().get() })
  0
}
