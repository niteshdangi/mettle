import std.thread
import std.sync.{mutex, condvar, rwlock, once, barrier, mpsc, tls}
import std.panic.{catch_panic, CatchResult}
import alloc.arc

type Flag {
  ready: core.sync.atomic.AtomicBool
  data: core.sync.atomic.AtomicUsize
}

fn discard<T>(value: take T): Unit {}

fn join_ok(h: take thread.JoinHandle<i32>): bool {
  let r = capture h.join()
  match take r { success(v) => true, failure(e) => false }
}

fn main(): i32 {
  // atomic publication: data written before the release store is visible
  let flag = arc.new(Flag(core.sync.atomic.AtomicBool.new(false), core.sync.atomic.AtomicUsize.new(0usize)))
  let theirs = flag.retain()
  let reader = thread.spawn(take fn(): i32 {
    while !theirs.get().ready.load(core.sync.atomic.Ordering.Acquire) { thread.yield_now() }
    if theirs.get().data.load(core.sync.atomic.Ordering.Relaxed) == 42usize { 0 } else { 1 }
  })
  flag.get().data.store(42usize, core.sync.atomic.Ordering.Relaxed)
  flag.get().ready.store(true, core.sync.atomic.Ordering.Release)
  let rr = capture reader.join()
  match take rr { success(v) => { if v != 0 { return 1 } }, failure(e) => { return 2 } }

  // channel: values arrive in order, then shutdown is observed
  let pair = mpsc.channel<i32>()
  let tx = pair.0
  let rx = pair.1
  let tx2 = tx.duplicate()
  let producer = thread.spawn(take fn(): i32 {
    var i = 0
    while i < 100 {
      let s = capture tx2.send(i + 0)
      match take s { success(u) => {}, failure(e) => { return 1 } }
      i = i + 1
    }
    0
  })
  discard(take tx)
  var sum = 0
  var open = true
  while open {
    let m = capture rx.recv()
    match take m { success(v) => { sum = sum + v }, failure(e) => { open = false } }
  }
  if sum != 4950 { return 3 }
  if !join_ok(producer) { return 4 }

  // send after the receiver is gone hands the value back
  let pair2 = mpsc.channel<i32>()
  let tx3 = pair2.0
  discard(take pair2.1)
  let lost = capture tx3.send(9)
  match take lost { success(u) => { return 5 }, failure(e) => { if e.value != 9 { return 6 } } }

  // barrier: exactly one leader per round
  let gate = arc.new(barrier.new(4usize))
  let leaders = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
  var workers = alloc.vec.new<thread.JoinHandle<i32>>()
  var k = 0
  while k < 4 {
    let g = gate.retain()
    let l = leaders.retain()
    workers.push(thread.spawn(take fn(): i32 {
      var round = 0
      while round < 3 {
        if g.get().wait() { let _old = l.get().fetch_add(1usize, core.sync.atomic.Ordering.Relaxed) }
        round = round + 1
      }
      0
    }))
    k = k + 1
  }
  var more = true
  while more {
    let next = workers.pop()
    match take next { present(w) => { if !join_ok(w) { return 7 } }, none => { more = false } }
  }
  if leaders.get().load(core.sync.atomic.Ordering.Relaxed) != 3usize { return 8 }

  // once: the initialiser runs a single time under contention
  let cell = arc.new(once.new())
  let runs = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
  var onces = alloc.vec.new<thread.JoinHandle<i32>>()
  k = 0
  while k < 4 {
    let c = cell.retain()
    let r = runs.retain()
    onces.push(thread.spawn(take fn(): i32 {
      let bump = fn(): Unit { let _old = r.get().fetch_add(1usize, core.sync.atomic.Ordering.Relaxed) }
      c.get().call_once(bump)
      0
    }))
    k = k + 1
  }
  more = true
  while more {
    let next = onces.pop()
    match take next { present(w) => { if !join_ok(w) { return 9 } }, none => { more = false } }
  }
  if runs.get().load(core.sync.atomic.Ordering.Relaxed) != 1usize { return 10 }
  cell.get().wait()
  cell.get().wait_force()

  // a panicking Once initializer is re-armed for the next caller
  let retry = once.new()
  let failed_init = catch_panic(fn(): Unit {
    retry.call_once(take fn(): Unit { panic("initializer failed") })
  })
  match failed_init {
    CatchResult.Panicked(info) => {},
    CatchResult.Returned(value) => { return 28 }
  }
  if retry.is_completed() { return 29 }
  retry.call_once(take fn(): Unit {})
  if !retry.is_completed() { return 30 }
  let forced = once.new()
  let force_ran = core.sync.atomic.AtomicBool.new(false)
  let force_saw_poison = core.sync.atomic.AtomicBool.new(false)
  forced.call_once_force(fn(state: once.OnceState): Unit {
    force_ran.store(true, core.sync.atomic.Ordering.Relaxed)
    force_saw_poison.store(state.is_poisoned(), core.sync.atomic.Ordering.Relaxed)
  })
  if !force_ran.load(core.sync.atomic.Ordering.Relaxed) ||
     force_saw_poison.load(core.sync.atomic.Ordering.Relaxed) { return 31 }

  // rwlock: readers share, writer excludes
  let lock = arc.new(rwlock.new(10))
  let l2 = lock.retain()
  let wr = thread.spawn(take fn(): i32 {
    let locked = capture l2.get().writer()
    let w = match take locked { success(g) => g, failure(e) => e.into_inner() }
    var g = w
    *g.get_mut() = 11
    0
  })
  if !join_ok(wr) { return 11 }
  let locked_reader = capture lock.get().reader()
  let r1 = match take locked_reader { success(g) => g, failure(e) => e.into_inner() }
  let r2 = capture lock.get().try_reader()
  match take r2 { success(g) => { if *g.get() != 11 { return 12 } }, failure(e) => { return 13 } }
  let blocked = capture lock.get().try_writer()
  match take blocked {
    success(g) => { return 14 },
    failure(e) => match e {
      mutex.TryLockError.WouldBlock => {},
      mutex.TryLockError.Poisoned(g) => { return 20 }
    }
  }
  if *r1.get() != 11 { return 15 }
  discard(take r1)

  // a writer panic poisons the rwlock and the error retains its guard
  let poisoned_lock = arc.new(rwlock.new(1))
  let poisoned_copy = poisoned_lock.retain()
  let panicker = thread.spawn(take fn(): i32 {
    let locked = capture poisoned_copy.get().writer()
    var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    *guard.get_mut() = 5
    panic("writer died")
  })
  let panic_result = capture panicker.join()
  match take panic_result {
    success(value) => { return 21 },
    failure(error) => { if error.code != 101 { return 22 } }
  }
  if !poisoned_lock.get().is_poisoned() { return 23 }
  let poisoned_read = capture poisoned_lock.get().reader()
  match take poisoned_read {
    success(guard) => { return 24 },
    failure(error) => {
      let guard = error.into_inner()
      if *guard.get() != 5 { return 25 }
    }
  }
  poisoned_lock.get().clear_poison()
  if poisoned_lock.get().is_poisoned() { return 26 }

  // condvar: a waiter wakes on notification
  let state = arc.new(mutex.new(false))
  let cv = arc.new(condvar.new())
  let s2 = state.retain()
  let c2 = cv.retain()
  let waiter = thread.spawn(take fn(): i32 {
    let o = capture s2.get().lock()
    var g = match take o { success(g) => g, failure(e) => e.into_inner() }
    g = c2.get().wait_while(g, take fn(ready: read bool): bool { !ready })
    0
  })
  let o = capture state.get().lock()
  var g = match take o { success(g) => g, failure(e) => e.into_inner() }
  *g.get_mut() = true
  cv.get().notify_all()
  discard(take g)
  if !join_ok(waiter) { return 16 }
  let timeout_lock = mutex.new(false)
  let timeout_locked = capture timeout_lock.lock()
  let timeout_guard = match take timeout_locked {
    success(guard) => guard,
    failure(error) => error.into_inner()
  }
  let timeout = cv.get().wait_timeout(timeout_guard, 0u64)
  if !timeout.1.timed_out { return 27 }

  // thread-local values are per thread
  let key = arc.new(tls.new<i32>())
  key.get().set(1)
  let k2 = key.retain()
  let other = thread.spawn(take fn(): i32 {
    if k2.get().is_set() { return 1 }
    k2.get().set(2)
    let seen = k2.get().with(take fn(v: read i32): i32 { v })
    match take seen { present(v) => { if v == 2 { 0 } else { 1 } }, none => 1 }
  })
  if !join_ok(other) { return 17 }
  let mine = key.get().with(take fn(v: read i32): i32 { v })
  match take mine { present(v) => { if v != 1 { return 18 } }, none => { return 19 } }
  0
}
