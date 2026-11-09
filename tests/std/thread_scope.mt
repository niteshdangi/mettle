import std.thread
import std.sync.barrier
import alloc.arc

type Tracker {
  drops: arc.Arc<core.sync.atomic.AtomicUsize>
  drop { let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst) }
}

fn main(): i32 {
  // scoped threads borrow locals and finish before the scope returns
  let data = 21
  let total = thread.scope(fn(read s: thread.Scope): i32 {
    let a = s.spawn(fn(): i32 { data + 1 })
    let b = s.spawn(fn(): i32 { data * 2 })
    let x = capture a.join()
    let y = capture b.join()
    let xv = match take x { success(v) => v, failure(e) => 0 }
    let yv = match take y { success(v) => v, failure(e) => 0 }
    xv + yv
  })
  if total != 64 { return 1 }

  // an unjoined scoped thread is joined at scope exit
  let hits = core.sync.atomic.AtomicUsize.new(0usize)
  let gate = arc.new(barrier.new(2usize))
  let child_gate = gate.retain()
  thread.scope(fn(read s: thread.Scope): Unit {
    let h = s.spawn(fn(): i32 {
      child_gate.get().wait()
      let _old = hits.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
      0
    })
    let _released = gate.get().wait()
  })
  if hits.load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 2 }

  // the scope joins its threads even when the scope body panics
  let finished = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
  let probe = finished.retain()
  let panic_gate = arc.new(barrier.new(2usize))
  let child_panic_gate = panic_gate.retain()
  let parent_panic_gate = panic_gate.retain()
  let outer = thread.spawn(take fn(): i32 {
    thread.scope(fn(read s: thread.Scope): i32 {
      let h = s.spawn(fn(): i32 {
        child_panic_gate.get().wait()
        let _old = probe.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
        0
      })
      parent_panic_gate.get().wait()
      panic("scope body failed")
    })
  })
  let outcome = capture outer.join()
  match take outcome { success(v) => { return 7 }, failure(e) => { if e.code != 101 { return 8 } } }
  if finished.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 9 }

  // the last owner destroys the value exactly once, wherever it is dropped
  let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
  let owner = arc.new(Tracker(drops.retain()))
  var k = 0
  var handles = alloc.vec.new<thread.JoinHandle<i32>>()
  while k < 6 {
    let mine = owner.retain()
    handles.push(thread.spawn(take fn(): i32 { thread.yield_now(); mine.strong_count() as i32 * 0 }))
    k = k + 1
  }
  var more = true
  while more {
    let next = handles.pop()
    match take next { present(h) => { let r = capture h.join() }, none => { more = false } }
  }
  if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize { return 3 }
  if owner.strong_count() != 1usize { return 4 }
  let observer = owner.downgrade()
  let moved = owner
  let last = thread.spawn(take fn(): i32 { 0 * moved.strong_count() as i32 })
  let lr = capture last.join()
  if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 5 }
  let up = observer.upgrade()
  match take up { present(a) => { return 6 }, none => {} }
  0
}
