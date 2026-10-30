// expect-error: region
import std.thread;

fn main(): i32 {
  thread.scope(fn(s: read thread.Scope): i32 {
    {
      let inner = 5
      let h = s.spawn(fn(): i32 { inner + 1 })
    }
    0
  })
}
