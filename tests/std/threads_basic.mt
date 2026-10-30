import std.thread
import std.sync.mutex
import alloc.arc

fn main(): i32 {
  let h = thread.spawn(take fn(): i32 { 7 })
  let r = capture h.join()
  match take r { success(v) => { if v != 7 { return 1 } }, failure(e) => { return 2 } }

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
