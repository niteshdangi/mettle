import std.thread
import std.sync.mutex
import alloc.arc

fn discard<T>(value: take T): Unit {}

fn main(): i32 {
  let lock = arc.new(mutex.new(1))
  let theirs = lock.retain()
  let t = thread.spawn(take fn(): i32 {
    let o = capture theirs.get().lock()
    var g = match take o { success(g) => g, failure(e) => e.into_inner() }
    *g.get_mut() = 2
    panic("holder died")
  })
  let r = capture t.join()
  match take r { success(v) => { return 1 }, failure(e) => {} }
  if !lock.get().is_poisoned() { return 2 }
  // the poisoned lock is still usable and the guard carries the data
  let o = capture lock.get().lock()
  var g = match take o { success(ok) => ok, failure(e) => e.into_inner() }
  if *g.get() != 2 { return 4 }
  discard(take g)
  // a guard drops its lock: a second acquisition does not deadlock
  let again = capture lock.get().try_lock()
  match take again { success(g) => {}, failure(e) => { return 5 } }
  0
}
