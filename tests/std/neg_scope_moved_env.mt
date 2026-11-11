// expect-error: region 8:13 borrowed source does not outlive the required region
import std.thread

// A `take` scope closure owns `data`; its environment dies when it returns.
fn main(): i32 {
  let data = 21
  thread.scope(take fn(read s: thread.Scope): i32 {
    let h = s.spawn(fn(): i32 { data + 1 })
    0
  })
}
