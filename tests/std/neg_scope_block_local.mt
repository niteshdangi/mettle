// expect-error: region 8:15 borrowed source does not outlive the required region
import std.thread

fn main(): i32 {
  thread.scope(fn(read s: thread.Scope): i32 {
    {
      let inner = 5
      let h = s.spawn(fn(): i32 { inner + 1 })
    }
    0
  })
}
