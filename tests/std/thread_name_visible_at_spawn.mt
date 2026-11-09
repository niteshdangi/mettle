// A Builder name is visible through the handle as soon as spawn returns,
// before the child has started running (regression: Linux once reported the
// process name until the child named itself).
import std.thread
import core.clone.Clone

fn main(): i32 {
  var round = 0
  while round < 64 {
    var builder = thread.Builder.new()
    builder.name("named-child")
    let spawned = capture builder.spawn(take fn(): i32 {
      thread.park()
      0
    })
    let handle = match take spawned { success(handle) => handle, failure(error) => { return 1 } }
    let child = handle.thread()
    match take child.name() {
      present(name) => { if name.as_text() != "named-child" { return 2 } },
      none => { return 3 }
    }
    child.unpark()
    let retained = child.clone()
    let joined = capture handle.join()
    match take joined { success(value) => { if value != 0 { return 4 } }, failure(error) => { return 5 } }
    match take retained.name() {
      present(name) => { if name.as_text() != "named-child" { return 6 } },
      none => { return 7 }
    }
    retained.unpark()
    round = round + 1
  }
  0
}
