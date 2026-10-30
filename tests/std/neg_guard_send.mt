// expect-error: type
import std::thread;
import std::sync::mutex;

fn main(): i32 {
  let lock = mutex::new(1)
  let o = capture lock.lock()
  let g = match take o { success(g) => g, failure(e) => e.into_inner() }
  thread::scope(take fn(s: read thread::Scope): i32 {
    let h = s.spawn(take fn(): i32 { *g.get() })
    0
  })
}
