// expect-exit: 0
// Evidence for the V1 mpsc channel operations: unbounded and bounded
// channels, send/recv/try_recv/recv_timeout, the iterator forms, disconnection
// in both directions, and the rendezvous channel. Sender and SyncSender clones
// count as additional producers.
import std.thread
import std.sync.mpsc
import core.clone.Clone
import core.fmt
import core.fmt.Debug
import core.text.Text

fn discard<T>(take value: T): Unit {}
fn require_debug<T: Debug>(read value: T, read prefix: Text): Unit {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { panic("mpsc Debug formatting failed") }
        }
    }
    assert(output.as_text().starts_with(read prefix), "mpsc Debug prefix")
}

// Disconnection follows the last sender; a dropped rendezvous_worker refuses sends.
fn checks_channel_basics(): i32 {
    let pair = mpsc.channel<i32>()
    require_debug(read pair.0, "Sender")
    require_debug(read pair.1, "Receiver")
    let tx = pair.0
    let rx = pair.1
    let sent = capture tx.send(10)
    match take sent { success(_) => {}, failure(_) => { return 10 } }
    let second = tx.duplicate()
    let also = capture second.send(11)
    match take also { success(_) => {}, failure(_) => { return 11 } }
    let cloned = tx.clone()
    let third = capture cloned.send(12)
    match take third { success(_) => {}, failure(_) => { return 12 } }
    let first = capture rx.recv()
    match take first { success(v) => { if v != 10 { return 13 } }, failure(_) => { return 14 } }
    let next = capture rx.recv()
    match take next { success(v) => { if v != 11 { return 15 } }, failure(_) => { return 16 } }
    let last = capture rx.recv()
    match take last { success(v) => { if v != 12 { return 17 } }, failure(_) => { return 18 } }

    // empty but with senders alive: try_recv reports no value, not disconnected
    let empty = capture rx.try_recv()
    match take empty {
        success(_) => { return 19 },
        failure(e) => { if e.disconnected { return 20 } }
    }
    discard(take tx)
    discard(take second)
    discard(take cloned)
    // the last sender is gone: recv fails and try_recv reports disconnection
    let closed = capture rx.recv()
    match take closed { success(_) => { return 21 }, failure(_) => {} }
    let closed_try = capture rx.try_recv()
    match take closed_try {
        success(_) => { return 22 },
        failure(e) => { if !e.disconnected { return 23 } }
    }

    // a dropped rendezvous_worker makes sends fail and hand the value back
    let orphan = mpsc.channel<i32>()
    let orphan_tx = orphan.0
    discard(take orphan.1)
    let refused = capture orphan_tx.send(77)
    match take refused {
        success(_) => { return 24 },
        failure(e) => { if e.value != 77 { return 25 } }
    }
    0
}

// recv_timeout returns a value when one arrives, times out when none does,
// and reports disconnection once every sender is gone.
fn checks_recv_timeout(): i32 {
    let pair = mpsc.channel<i32>()
    let tx = pair.0
    let rx = pair.1
    let quiet = capture rx.recv_timeout(0u64)
    match take quiet {
        success(_) => { return 30 },
        failure(e) => { if !e.timed_out || e.disconnected { return 31 } }
    }
    let delivered = capture tx.send(40)
    match take delivered { success(_) => {}, failure(_) => { return 32 } }
    let value = capture rx.recv_timeout(1000000000u64)
    match take value {
        success(v) => { if v != 40 { return 33 } },
        failure(_) => { return 34 }
    }
    discard(take tx)
    let closed = capture rx.recv_timeout(1000000000u64)
    match take closed {
        success(_) => { return 35 },
        failure(e) => { if !e.disconnected || e.timed_out { return 36 } }
    }
    0
}

// try_iter yields exactly the queued values; iter drains until disconnection;
// into_iter moves the rendezvous_worker into an owning iterator.
fn checks_iterators(): i32 {
    let pair = mpsc.channel<i32>()
    let tx = pair.0
    var rx = pair.1
    var index = 1
    while index <= 3 {
        let sent = capture tx.send(index * 100)
        match take sent { success(_) => {}, failure(_) => { return 50 } }
        index += 1
    }
    var queued = rx.try_iter()
    var total = 0
    var count = 0
    while true {
        match queued.next() {
            present(v) => { total += v; count += 1 },
            none => { break }
        }
    }
    if count != 3 || total != 600 { return 51 }
    if queued.next().is_present() { return 52 }

    // the blocking iterator ends only after the producer disconnects
    let producer = thread.spawn(take fn(): i32 {
        var i = 1
        while i <= 4 {
            let sent = capture tx.send(i + 0)
            match take sent { success(_) => {}, failure(_) => { return 1 } }
            i += 1
        }
        0
    })
    var drained = rx.iter()
    var sum = 0
    var seen = 0
    while true {
        match drained.next() {
            present(v) => { sum += v; seen += 1 },
            none => { break }
        }
    }
    let produced = capture producer.join()
    match take produced { success(code) => { if code != 0 { return 53 } }, failure(_) => { return 54 } }
    if seen != 4 || sum != 10 { return 55 }

    // into_iter consumes the rendezvous_worker; the queued values come out in order
    let owned_pair = mpsc.channel<i32>()
    let owned_tx = owned_pair.0
    let sent_one = capture owned_tx.send(7)
    match take sent_one { success(_) => {}, failure(_) => { return 56 } }
    let sent_two = capture owned_tx.send(8)
    match take sent_two { success(_) => {}, failure(_) => { return 57 } }
    discard(take owned_tx)
    var owned = owned_pair.1.into_iter()
    let a = owned.next()
    let b = owned.next()
    let finished = owned.next()
    if a.unwrap() != 7 || b.unwrap() != 8 || finished.is_present() { return 58 }
    0
}

// A bounded channel refuses try_send when full and returns the value; a
// rendezvous channel blocks until the rendezvous_worker takes the message.
fn checks_bounded_and_rendezvous(): i32 {
    let bounded = mpsc.sync_channel<i32>(1usize)
    require_debug(read bounded.0, "SyncSender")
    require_debug(read bounded.1, "Receiver")
    let bounded_tx = bounded.0
    let bounded_rx = bounded.1
    let accepted = capture bounded_tx.try_send(1)
    match take accepted { success(_) => {}, failure(_) => { return 60 } }
    let full = capture bounded_tx.try_send(2)
    match take full {
        success(_) => { return 61 },
        failure(e) => { if e.value != 2 || e.disconnected { return 62 } }
    }
    let drained = capture bounded_rx.recv()
    match take drained { success(v) => { if v != 1 { return 63 } }, failure(_) => { return 64 } }
    let cloned = bounded_tx.clone()
    let refilled = capture cloned.send(3)
    match take refilled { success(_) => {}, failure(_) => { return 65 } }
    discard(take cloned)
    discard(take bounded_tx)
    let last = capture bounded_rx.recv()
    match take last { success(v) => { if v != 3 { return 66 } }, failure(_) => { return 67 } }
    let done = capture bounded_rx.recv()
    match take done { success(_) => { return 68 }, failure(_) => {} }

    let rendezvous = mpsc.sync_channel<i32>(0usize)
    let rendezvous_tx = rendezvous.0
    let rendezvous_rx = rendezvous.1
    let no_receiver = capture rendezvous_tx.try_send(4)
    match take no_receiver {
        success(_) => { return 69 },
        failure(e) => { if e.value != 4 || e.disconnected { return 70 } }
    }
    let rendezvous_worker = thread.spawn(take fn(): i32 {
        let got = capture rendezvous_rx.recv()
        match take got { success(v) => { if v == 5 { 0 } else { 1 } }, failure(_) => { 2 } }
    })
    let handed = capture rendezvous_tx.send(5)
    match take handed { success(_) => {}, failure(_) => { return 71 } }
    let received = capture rendezvous_worker.join()
    match take received { success(code) => { if code != 0 { return 72 } }, failure(_) => { return 73 } }
    0
}

// A shared receiver view iterates through the same queue as the owner.
fn checks_borrowed_receiver(): i32 {
    let pair = mpsc.channel<i32>()
    let tx = pair.0
    let rx = pair.1
    let first = capture tx.send(7)
    match take first { success(_) => {}, failure(_) => { return 60 } }
    let second = capture tx.send(8)
    match take second { success(_) => {}, failure(_) => { return 61 } }
    core.mem.drop(tx)
    var view = read rx
    var total = 0
    while true {
        match view.next() {
            present(value) => { total += value },
            none => { break }
        }
    }
    if total != 15 { return 62 }
    0
}

fn main(): i32 {
    let first = checks_channel_basics()
    if first != 0 { return first }
    let second = checks_recv_timeout()
    if second != 0 { return second }
    let third = checks_iterators()
    if third != 0 { return third }
    let fourth = checks_borrowed_receiver()
    if fourth != 0 { return fourth }
    checks_bounded_and_rendezvous()
}
