// expect-error: type
import std::thread;

fn main(): i32 {
  let cell = core::cell::Cell::new(1)
  thread::scope(fn(s: read thread::Scope): i32 {
    let reader = fn(): i32 { cell.get() }
    let h = s.spawn(reader)
    0
  })
}
