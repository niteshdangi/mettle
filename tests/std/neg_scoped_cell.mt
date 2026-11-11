// expect-error: type 8:13 unsatisfied interface bound 'Transferable'
import std.thread

fn main(): i32 {
  let cell = core.cell.Cell.new(1)
  thread.scope(fn(read s: thread.Scope): i32 {
    let reader = fn(): i32 { cell.get() }
    let h = s.spawn(reader)
    0
  })
}
