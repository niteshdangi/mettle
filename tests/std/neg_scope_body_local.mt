// expect-error: region
import std.thread

// The spawned thread may outlive the scope body's locals: the scope joins
// only after its closure has returned.
fn main(): i32 {
  thread.scope(fn(s: read thread.Scope): i32 {
    let inner = 5
    let h = s.spawn(fn(): i32 { thread.sleep_nanos(20000000u64); inner + 1 })
    0
  })
}
