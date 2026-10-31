import std.thread
import std.sync.{mutex, condvar, rwlock, once, once_lock, barrier, mpsc, tls}
import std.panic.{catch_panic, CatchResult}
import alloc.arc
import core.iter.Iterator

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

  let iter_pair = mpsc.channel<i32>()
  let iter_tx = iter_pair.0
  let iter_rx = iter_pair.1
  let _first_send = capture iter_tx.send(4)
  let _second_send = capture iter_tx.send(5)
  discard(take iter_tx)
  var blocking_iter = iter_rx.iter()
  var iter_sum = 0
  while true {
    match take blocking_iter.next() {
      present(value) => { iter_sum += value },
      none => { break }
    }
  }
  if iter_sum != 9 { return 54 }

  let try_pair = mpsc.channel<i32>()
  let try_tx = try_pair.0
  let try_rx = try_pair.1
  let _try_send = capture try_tx.send(6)
  var immediate_iter = try_rx.try_iter()
  match take immediate_iter.next() {
    present(value) => { if value != 6 { return 55 } },
    none => { return 56 }
  }
  match take immediate_iter.next() {
    present(value) => { return 57 },
    none => {}
  }

  let owned_pair = mpsc.channel<i32>()
  let owned_tx = owned_pair.0
  let owned_rx = owned_pair.1
  let _owned_send = capture owned_tx.send(8)
  discard(take owned_tx)
  var owned_iter = owned_rx.into_iter()
  match take owned_iter.next() {
    present(value) => { if value != 8 { return 58 } },
    none => { return 59 }
  }
  match take owned_iter.next() {
    present(value) => { return 60 },
    none => {}
  }

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
        if g.get().wait().is_leader() {
          let _old = l.get().fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        }
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

  // a panicking Once initializer poisons the cell until forced recovery
  let retry = once.new()
  let failed_init = catch_panic(fn(): Unit {
    retry.call_once(take fn(): Unit { panic("initializer failed") })
  })
  match failed_init {
    CatchResult.Panicked(info) => {},
    CatchResult.Returned(value) => { return 28 }
  }
  if retry.is_completed() { return 29 }
  let poisoned_call = catch_panic(fn(): Unit {
    retry.call_once(take fn(): Unit {})
  })
  match poisoned_call {
    CatchResult.Panicked(info) => {},
    CatchResult.Returned(value) => { return 30 }
  }
  let poisoned_wait = catch_panic(fn(): Unit { retry.wait() })
  match poisoned_wait {
    CatchResult.Panicked(info) => {},
    CatchResult.Returned(value) => { return 38 }
  }
  retry.wait_force()
  let recovered = core.sync.atomic.AtomicBool.new(false)
  let saw_poison = core.sync.atomic.AtomicBool.new(false)
  retry.call_once_force(fn(state: once.OnceState): Unit {
    recovered.store(true, core.sync.atomic.Ordering.Relaxed)
    saw_poison.store(state.is_poisoned(), core.sync.atomic.Ordering.Relaxed)
  })
  if !recovered.load(core.sync.atomic.Ordering.Relaxed) ||
     !saw_poison.load(core.sync.atomic.Ordering.Relaxed) { return 31 }
  if !retry.is_completed() { return 32 }
  let forced = once.new()
  let force_ran = core.sync.atomic.AtomicBool.new(false)
  let force_saw_poison = core.sync.atomic.AtomicBool.new(false)
  forced.call_once_force(fn(state: once.OnceState): Unit {
    force_ran.store(true, core.sync.atomic.Ordering.Relaxed)
    force_saw_poison.store(state.is_poisoned(), core.sync.atomic.Ordering.Relaxed)
  })
  if !force_ran.load(core.sync.atomic.Ordering.Relaxed) ||
     force_saw_poison.load(core.sync.atomic.Ordering.Relaxed) { return 33 }

  // OnceLock retries a panicking initializer and publishes one value to readers.
  let cell = arc.new(once_lock.new<i32>())
  let attempts = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
  var readers = alloc.vec.new<thread.JoinHandle<i32>>()
  k = 0
  while k < 4 {
    let shared_cell = cell.retain()
    let shared_attempts = attempts.retain()
    readers.push(thread.spawn(take fn(): i32 {
      let value = shared_cell.get().get_or_init(fn(): i32 {
        let _previous = shared_attempts.get().fetch_add(
          1usize, core.sync.atomic.Ordering.Relaxed
        )
        73
      })
      if value == 73 { 0 } else { 1 }
    }))
    k += 1
  }
  more = true
  while more {
    let next = readers.pop()
    match take next {
      present(worker) => { if !join_ok(worker) { return 39 } },
      none => { more = false }
    }
  }
  if attempts.get().load(core.sync.atomic.Ordering.Relaxed) != 1usize {
    return 40
  }
  let duplicate = capture cell.get().set(74)
  match take duplicate {
    success(value) => { return 41 },
    failure(error) => { if error.into_inner() != 74 { return 42 } }
  }
  var manual_cell = once_lock.new<i32>()
  let inserted = capture manual_cell.set(76)
  if inserted.is_failure() { return 46 }
  match manual_cell.get_mut() {
    present(value) => { *value = 77 },
    none => { return 47 }
  }
  match manual_cell.take() {
    present(value) => { if value != 77 { return 48 } },
    none => { return 49 }
  }
  let reinserted = capture manual_cell.set(78)
  if reinserted.is_failure() { return 50 }
  match manual_cell.into_inner() {
    present(value) => { if value != 78 { return 51 } },
    none => { return 52 }
  }
  let waiting_cell = arc.new(once_lock.new<i32>())
  let waiting_copy = waiting_cell.retain()
  let waiting_thread = thread.spawn(take fn(): i32 {
    if waiting_copy.get().wait() == 79 { 0 } else { 1 }
  })
  let initialized = capture waiting_cell.get().set(79)
  if initialized.is_failure() || !join_ok(waiting_thread) { return 53 }
  let retry_cell = once_lock.new<i32>()
  let failed_once_lock_init = catch_panic(fn(): Unit {
    retry_cell.get_or_init(take fn(): i32 { panic("OnceLock initializer failed") })
  })
  match failed_once_lock_init {
    CatchResult.Panicked(info) => {},
    CatchResult.Returned(value) => { return 43 }
  }
  match retry_cell.get() {
    present(value) => { return 44 },
    none => {}
  }
  let recovered_value = retry_cell.get_or_init(fn(): i32 { 75 })
  if recovered_value != 75 { return 45 }

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

  // Unshared locks expose mutation and extraction without a guard.
  var unique_mutex = mutex.new(40)
  *unique_mutex.get_mut() = 41
  let mutex_value = capture unique_mutex.into_inner()
  match take mutex_value {
    success(value) => { if value != 41 { return 34 } },
    failure(error) => { return 35 }
  }
  var unique_rwlock = rwlock.new(50)
  *unique_rwlock.get_mut() = 51
  let rwlock_value = capture unique_rwlock.into_inner()
  match take rwlock_value {
    success(value) => { if value != 51 { return 36 } },
    failure(error) => { return 37 }
  }

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
  let timeout = cv.get().wait_timeout_while(
    timeout_guard, 0u64, take fn(ready: read bool): bool { !ready }
  )
  if !timeout.1.timed_out() { return 27 }

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
