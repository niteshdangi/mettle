import std.thread
import std.sync.mpsc
import alloc.arc

fn discard<T>(take value: T): Unit {}

fn main(): i32 {
  // a full bounded queue blocks the sender until the receiver makes room
  let pair = mpsc.sync_channel<i32>(2usize)
  let tx = pair.0
  let rx = pair.1
  let sent = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
  let probe = sent.retain()
  let producer = thread.spawn(take fn(): i32 {
    var i = 0
    while i < 3 {
      let s = capture tx.send(i + 0)
      match take s { success(u) => {}, failure(e) => { return 1 } }
      let _old = probe.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
      i = i + 1
    }
    0
  })
  while sent.get().load(core.sync.atomic.Ordering.SeqCst) < 2usize {
    thread.yield_now()
  }
  if sent.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize { return 1 }
  let first = capture rx.recv()
  match take first { success(v) => { if v != 0 { return 2 } }, failure(e) => { return 3 } }
  let joined = capture producer.join()
  match take joined { success(v) => { if v != 0 { return 4 } }, failure(e) => { return 5 } }
  if sent.get().load(core.sync.atomic.Ordering.SeqCst) != 3usize { return 6 }

  // try_send reports a full queue and hands the value back
  let pair2 = mpsc.sync_channel<i32>(1usize)
  let tx2 = pair2.0
  let rx2 = pair2.1
  let a = capture tx2.try_send(1)
  match take a { success(u) => {}, failure(e) => { return 7 } }
  let b = capture tx2.try_send(2)
  match take b { success(u) => { return 8 }, failure(e) => { if e.value != 2 || e.disconnected { return 9 } } }

  // blocked senders fail once the receiver is dropped
  let blocked = thread.spawn(take fn(): i32 {
    let s = capture tx2.send(3)
    match take s { success(u) => 1, failure(e) => if e.value == 3 { 0 } else { 2 } }
  })
  thread.sleep_nanos(30000000u64)
  discard(take rx2)
  let br = capture blocked.join()
  match take br { success(v) => { if v != 0 { return 10 } }, failure(e) => { return 11 } }

  // several producers feed one consumer through a small queue
  let pair3 = mpsc.sync_channel<i32>(3usize)
  let base = pair3.0
  let rx3 = pair3.1
  var workers = alloc.vec.new<thread.JoinHandle<i32>>()
  var k = 0
  while k < 4 {
    let mine = base.duplicate()
    workers.push(thread.spawn(take fn(): i32 {
      var i = 1
      while i <= 50 {
        let s = capture mine.send(i + 0)
        match take s { success(u) => {}, failure(e) => { return 1 } }
        i = i + 1
      }
      0
    }))
    k = k + 1
  }
  discard(take base)
  var sum = 0
  var open = true
  while open {
    let m = capture rx3.recv()
    match take m { success(v) => { sum = sum + v }, failure(e) => { open = false } }
  }
  if sum != 4 * 1275 { return 12 }
  var more = true
  while more {
    let next = workers.pop()
    match take next {
      present(h) => { let r = capture h.join()
        match take r { success(v) => { if v != 0 { return 13 } }, failure(e) => { return 14 } } },
      none => { more = false }
    }
  }
  0
}
