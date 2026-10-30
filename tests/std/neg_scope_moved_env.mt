// expect-error: region
import std::thread;

// A `take` scope closure owns `data`; its environment dies when it returns.
fn main(): i32 {
  let data = 21
  thread::scope(take fn(s: read thread::Scope): i32 {
    let h = s.spawn(fn(): i32 { data + 1 })
    0
  })
}
