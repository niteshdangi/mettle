import std.thread
import std.sync.mutex
import alloc.arc

fn main(): i32 {
  if thread.current().raw == 0usize ||
     thread.available_parallelism() == 0usize || thread.panicking() {
    return 8
  }
  thread.yield_now()
  thread.sleep(std.time.from_millis(1u64))

  let h = thread.spawn(take fn(): i32 { 7 })
  let r = capture h.join()
  match take r { success(v) => { if v != 7 { return 1 } }, failure(e) => { return 2 } }

  var builder = thread.Builder.new()
  builder.name("parking-child")
  let parked = builder.spawn(take fn(): i32 {
    thread.park()
    9
  })
  let child = parked.thread()
  if child.id().raw == thread.current().raw { return 9 }
  match child.name() {
    present(name) => { if name != "parking-child" { return 10 } },
    none => { return 11 }
  }
  // An unpark before park stores a token for the next park.
  child.unpark()
  let parked_result = capture parked.join()
  match take parked_result {
    success(value) => { if value != 9 { return 12 } },
    failure(error) => { return 13 }
  }
  thread.park_timeout_ms(1u64)

  // a panic ends only its thread and join reports it
  let p = thread.spawn(take fn(): i32 { panic("boom") })
  let pr = capture p.join()
  match take pr { success(v) => { return 3 }, failure(e) => { if e.code != 101 { return 4 } } }

  // contended counter behind Arc<Mutex>
  let counter = arc.new(mutex.new(0))
  var handles = alloc.vec.new<thread.JoinHandle<i32>>()
  var t = 0
  while t < 4 {
    let mine = counter.retain()
    handles.push(thread.spawn(take fn(): i32 {
      var i = 0
      while i < 2000 {
        let o = capture mine.get().lock()
        var g = match take o { success(g) => g, failure(e) => e.into_inner() }
        *g.get_mut() = *g.get() + 1
        i = i + 1
      }
      0
    }))
    t = t + 1
  }
  var joined = true
  var more = true
  while more {
    let next = handles.pop()
    match take next {
      present(handle) => { let jr = capture handle.join(); match take jr { success(v) => {}, failure(e) => { joined = false } } },
      none => { more = false }
    }
  }
  if !joined { return 5 }
  let o = capture counter.get().lock()
  let total = match take o { success(g) => *g.get(), failure(e) => -1 }
  if total != 8000 { return 6 }
  if counter.strong_count() != 1usize { return 7 }
  0
}
