import std.thread
import std.sync.mpsc
import alloc.arc
import core.iter.Iterator

fn main(): i32 {
    let unbounded = mpsc.channel<i32>()
    let unbounded_tx = unbounded.0
    let unbounded_rx = unbounded.1
    let accepted = capture unbounded_tx.try_send(5)
    match take accepted { success(_) => {}, failure(_) => { return 1 } }
    let unbounded_value = capture unbounded_rx.try_recv()
    match take unbounded_value {
        success(value) => { if value != 5 { return 2 } },
        failure(_) => { return 3 }
    }
    discard(take unbounded_rx)
    let disconnected = capture unbounded_tx.try_send(6)
    match take disconnected {
        success(_) => { return 4 },
        failure(error) => {
            if error.value != 6 || !error.disconnected { return 5 }
        }
    }

    let rendezvous = mpsc.sync_channel<i32>(0usize)
    let tx = rendezvous.0
    let rx = rendezvous.1
    let no_waiter = capture tx.try_send(6)
    match take no_waiter {
        success(_) => { return 6 },
        failure(error) => {
            if error.value != 6 || error.disconnected { return 7 }
        }
    }
    let started = core.sync.atomic.AtomicUsize.new(0usize)
    let probe = arc.new(started)
    let worker_probe = probe.retain()
    let worker = thread.spawn(take fn(): i32 {
        worker_probe.get().store(1usize, core.sync.atomic.Ordering.Release)
        let sent = capture tx.send(7)
        match take sent {
            success(_) => {
                worker_probe.get().store(2usize, core.sync.atomic.Ordering.Release)
                0
            },
            failure(_) => 1
        }
    })
    thread.sleep_nanos(20000000u64)
    if probe.get().load(core.sync.atomic.Ordering.Acquire) != 1usize { return 8 }
    let received = capture rx.recv()
    match take received {
        success(value) => { if value != 7 { return 9 } },
        failure(_) => { return 10 }
    }
    let joined = capture worker.join()
    match take joined {
        success(value) => { if value != 0 { return 11 } },
        failure(_) => { return 12 }
    }
    if probe.get().load(core.sync.atomic.Ordering.Acquire) != 2usize { return 13 }

    let empty = mpsc.channel<i32>()
    let timeout = capture empty.1.recv_timeout(1000000u64)
    match take timeout {
        success(_) => { return 14 },
        failure(error) => {
            if !error.timed_out || error.disconnected { return 15 }
        }
    }

    let bounded = mpsc.sync_channel<i32>(1usize)
    let send = capture bounded.0.send(10)
    match take send { success(_) => {}, failure(_) => { return 16 } }
    let try_full = capture bounded.0.try_send(11)
    match take try_full {
        success(_) => { return 17 },
        failure(error) => {
            if error.value != 11 || error.disconnected { return 18 }
        }
    }
    let full = capture bounded.0.send_timeout(12, 1000000u64)
    match take full {
        success(_) => { return 19 },
        failure(error) => {
            if error.value != 12 || !error.timed_out || error.disconnected { return 20 }
        }
    }
    let first = capture bounded.1.recv()
    match take first { success(value) => { if value != 10 { return 21 } }, failure(_) => { return 22 } }
    let no_message = capture bounded.1.try_recv()
    match take no_message {
        success(_) => { return 23 },
        failure(error) => { if error.disconnected { return 24 } }
    }

    let left = mpsc.channel<i32>()
    let right = mpsc.channel<i32>()
    let right_tx = right.0
    let producer = thread.spawn(take fn(): i32 {
        thread.sleep_nanos(10000000u64)
        let sent = capture right_tx.send(42)
        match take sent { success(_) => 0, failure(_) => 1 }
    })
    var selection = mpsc.select(read left.1)
    let right_index = selection.add(read right.1)
    if right_index != 1usize { return 25 }
    let selected = capture selection.select()
    match take selected {
        success(index) => { if index != 1usize { return 26 } },
        failure(_) => { return 27 }
    }
    let selected_value = capture right.1.recv()
    match take selected_value { success(value) => { if value != 42 { return 28 } }, failure(_) => { return 29 } }
    let producer_result = capture producer.join()
    match take producer_result {
        success(value) => { if value != 0 { return 30 } },
        failure(_) => { return 31 }
    }

    let stream = mpsc.channel<i32>()
    let stream_tx = stream.0
    var stream_rx = stream.1
    let _a = capture stream_tx.send(2)
    let _b = capture stream_tx.send(3)
    discard(take stream_tx)
    var sum = 0
    var open = true
    while open {
        match take stream_rx.next() {
            present(value) => { sum += value },
            none => { open = false }
        }
    }
    if sum != 5 { return 32 }

    let closed_receiver = mpsc.channel<i32>()
    discard(take closed_receiver.0)
    let closed_receive = capture closed_receiver.1.recv_timeout(1000000u64)
    match take closed_receive {
        success(_) => { return 33 },
        failure(error) => {
            if error.timed_out || !error.disconnected { return 34 }
        }
    }

    let closed_sender = mpsc.sync_channel<i32>(1usize)
    let closed_tx = closed_sender.0
    discard(take closed_sender.1)
    let closed_send = capture closed_tx.send_timeout(13, 1000000u64)
    match take closed_send {
        success(_) => { return 35 },
        failure(error) => {
            if error.value != 13 || error.timed_out || !error.disconnected { return 36 }
        }
    }
    0
}

fn discard<T>(take value: T): Unit {}
