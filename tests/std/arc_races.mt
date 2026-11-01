import std.thread
import alloc.arc

type Tracker {
  drops: arc.Arc<core.sync.atomic.AtomicUsize>
  drop { let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst) }
}

fn discard<T>(value: take T): Unit {}

// Weak.upgrade races the final strong drop: each round the value must be
// destroyed exactly once and upgrades must never observe a dead value.
fn round(drops: read arc.Arc<core.sync.atomic.AtomicUsize>): i32 {
  let owner = arc.new(Tracker(drops.retain()))
  var handles = alloc.vec.new<thread.JoinHandle<i32>>()
  var k = 0
  while k < 3 {
    let observer = owner.downgrade()
    handles.push(thread.spawn(take fn(): i32 {
      var i = 0
      var bad = 0
      while i < 200 {
        let up = observer.upgrade()
        match take up { present(a) => { if a.strong_count() == 0usize { bad = bad + 1 } }, none => {} }
        i = i + 1
      }
      bad
    }))
    k = k + 1
  }
  discard(take owner)
  var more = true
  var bad = 0
  while more {
    let next = handles.pop()
    match take next {
      present(h) => { let r = capture h.join(); match take r { success(v) => { bad = bad + v }, failure(e) => { bad = bad + 1000 } } },
      none => { more = false }
    }
  }
  bad
}

fn main(): i32 {
  let owner = arc.new(7)
  let retained = owner.retain()
  if !owner.ptr_eq(retained) { return 3 }
  let observer = owner.downgrade()
  let duplicate = observer.retain()
  if !observer.ptr_eq(duplicate) || observer.weak_count() != 2usize { return 4 }
  discard(take owner)
  discard(take retained)
  if observer.strong_count() != 0usize || observer.weak_count() != 0usize { return 5 }
  match observer.upgrade() { present(_) => { return 6 }, none => {} }

  let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
  var r = 0
  while r < 20 {
    let result = round(drops)
    if result != 0 { return 7 }
    r = r + 1
  }
  if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 20usize { return 8 }
  0
}
