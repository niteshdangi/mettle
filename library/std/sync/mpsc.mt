import super.mutex
import super.condition
import super.super.time
import alloc.arc.Arc
import alloc.vec.List
import alloc.vec_deque.Deque
import core.iter.Iterator
import core.clone.Clone
import core.fmt.{Debug, Error, Formatter}

extern "C" {
    unsafe fn mettle_rt_select_epoch(): u64;
    unsafe fn mettle_rt_select_wait(epoch: u64): Unit;
    unsafe fn mettle_rt_select_notify(): Unit;
}

type Envelope<T> {
    value: T
    receipt: Arc<core.sync.atomic.AtomicBool>?
}

fn accepted(read receipt: Arc<core.sync.atomic.AtomicBool>?): bool {
    match receipt {
        present(flag) => flag.get().load(core.sync.atomic.Ordering.Acquire),
        none => false
    }
}

fn receive<T>(take envelope: Envelope<T>): T {
    match envelope.receipt {
        present(flag) => flag.get().store(true, core.sync.atomic.Ordering.Release),
        none => {}
    }
    envelope.value
}

type Shared<T> {
    queue: mutex.Mutex<Deque<Envelope<T>>>
    ready: condition.Condition
    space: condition.Condition
    bound: usize
    rendezvous: bool
    waiting_receivers: core.sync.atomic.AtomicUsize
    senders: core.sync.atomic.AtomicUsize
    open: core.sync.atomic.AtomicBool
}

pub copy type SendError<T> { pub value: T }
pub copy type RecvError {}
pub copy type TryRecvError { pub disconnected: bool }
pub copy type TrySendError<T> { pub value: T; pub disconnected: bool }
pub copy type RecvTimeoutError { pub timed_out: bool; pub disconnected: bool }
pub type SendTimeoutError<T> {
    pub value: T
    pub timed_out: bool
    pub disconnected: bool
}
pub copy type EmptySelect {}

// Sender for an unbounded FIFO channel.
pub type Sender<T> {
    chan: Arc<Shared<T>>
    drop {
        let previous = self.chan.get().senders.fetch_sub(1usize, core.sync.atomic.Ordering.AcqRel)
        if previous == 1usize {
            let locked = capture self.chan.get().queue.lock()
            let _guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
            self.chan.get().ready.notify_all()
            unsafe { mettle_rt_select_notify() }
        }
    }
}

// The channel's sole receiver; dropping it disconnects every sender.
pub type Receiver<T> {
    chan: Arc<Shared<T>>
    drop {
        var discarded = alloc.vec_deque.new<Envelope<T>>()
        {
            let locked = capture self.chan.get().queue.lock()
            var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
            self.chan.get().open.store(false, core.sync.atomic.Ordering.Release)
            if self.chan.get().rendezvous {
                match take guard.get_mut().pop_front() {
                    present(envelope) => {
                        if envelope.receipt.is_present() {
                            guard.get_mut().push_back(envelope)
                        } else {
                            discarded.push_back(envelope)
                        }
                    },
                    none => {}
                }
            } else {
                discarded = core.mem.replace(guard.get_mut(), alloc.vec_deque.new<Envelope<T>>())
            }
            self.chan.get().ready.notify_all()
            self.chan.get().space.notify_all()
            unsafe { mettle_rt_select_notify() }
        }
    }
}
extend<T> Receiver<T> not Shareable

// Sender for a bounded channel; capacity zero requires a waiting receiver.
pub type SyncSender<T> {
    chan: Arc<Shared<T>>
    drop {
        let previous = self.chan.get().senders.fetch_sub(1usize, core.sync.atomic.Ordering.AcqRel)
        if previous == 1usize {
            let locked = capture self.chan.get().queue.lock()
            let _guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
            self.chan.get().ready.notify_all()
            unsafe { mettle_rt_select_notify() }
        }
    }
}

fn new_shared<T>(bound: usize, rendezvous: bool): Arc<Shared<T>> {
    alloc.arc.new(Shared(
        mutex.new(alloc.vec_deque.new<Envelope<T>>()),
        condition.new(),
        condition.new(),
        bound,
        rendezvous,
        core.sync.atomic.AtomicUsize.new(0usize),
        core.sync.atomic.AtomicUsize.new(1usize),
        core.sync.atomic.AtomicBool.new(true)
    ))
}

pub fn channel<T>(): (Sender<T>, Receiver<T>) {
    let chan = new_shared<T>(0usize, false)
    let other = chan.retain()
    (Sender(chan), Receiver(other))
}

// A zero bound is a rendezvous: send returns only after a receiver takes the
// message.
pub fn sync_channel<T>(bound: usize): (SyncSender<T>, Receiver<T>) {
    let chan = new_shared<T>(bound, bound == 0usize)
    let other = chan.retain()
    (SyncSender(chan), Receiver(other))
}

extend<T> Sender<T> {
    pub fn send(take value: T): Unit throws SendError<T> {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if !self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
            throw SendError(value)
        }
        guard.get_mut().push_back(Envelope(value, none))
        self.chan.get().ready.notify_one()
        unsafe { mettle_rt_select_notify() }
    }

    pub fn try_send(take value: T): Unit throws TrySendError<T> {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if !self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
            throw TrySendError(value, true)
        }
        guard.get_mut().push_back(Envelope(value, none))
        self.chan.get().ready.notify_one()
        unsafe { mettle_rt_select_notify() }
    }

    pub fn duplicate(): Sender<T> {
        let _previous = self.chan.get().senders.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        Sender(self.chan.retain())
    }
}

extend<T> SyncSender<T> {
    pub fn send(take value: T): Unit throws SendError<T> {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        let rendezvous = self.chan.get().bound == 0usize
        while self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) &&
              (if rendezvous {
                  !guard.get().is_empty() || self.chan.get().waiting_receivers.load(core.sync.atomic.Ordering.Relaxed) == 0usize
              } else {
                  guard.get().len() >= self.chan.get().bound
              }) {
            let waited = capture self.chan.get().space.wait(guard)
            guard = match take waited { success(g) => g, failure(e) => e.into_inner() }
        }
        if !self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
            throw SendError(value)
        }
        let receipt: Arc<core.sync.atomic.AtomicBool>? = if rendezvous {
            present(alloc.arc.new(core.sync.atomic.AtomicBool.new(false)))
        } else { none }
        let queued_receipt = match receipt {
            present(flag) => present(flag.retain()),
            none => none
        }
        guard.get_mut().push_back(Envelope(value, queued_receipt))
        self.chan.get().ready.notify_one()
        unsafe { mettle_rt_select_notify() }
        if rendezvous {
            // Only receipt publication acknowledges this sender's own message.
            while !accepted(read receipt) &&
                  self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
                let waited = capture self.chan.get().space.wait(guard)
                guard = match take waited { success(g) => g, failure(e) => e.into_inner() }
            }
            if !accepted(read receipt) {
                let returned = guard.get_mut().pop_back()
                self.chan.get().space.notify_all()
                match take returned {
                    present(unsent) => throw SendError(unsent.value),
                    none => core.intrinsics.abort()
                }
            }
        }
    }

    pub fn try_send(take value: T): Unit throws TrySendError<T> {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if !self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
            throw TrySendError(value, true)
        }
        let rendezvous = self.chan.get().bound == 0usize
        let full = if rendezvous {
            !guard.get().is_empty() || self.chan.get().waiting_receivers.load(core.sync.atomic.Ordering.Relaxed) == 0usize
        } else {
            guard.get().len() >= self.chan.get().bound
        }
        if full {
            throw TrySendError(value, false)
        }
        guard.get_mut().push_back(Envelope(value, none))
        self.chan.get().ready.notify_one()
        unsafe { mettle_rt_select_notify() }
    }

    // Blocks for at most `timeout_nanos`, returning the value if not accepted.
    pub fn send_timeout(take value: T, timeout_nanos: u64): Unit throws SendTimeoutError<T> {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        let rendezvous = self.chan.get().bound == 0usize
        let started = time.now()
        while true {
            if !self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
                throw SendTimeoutError(value, false, true)
            }
            let available = if rendezvous {
                guard.get().is_empty() && self.chan.get().waiting_receivers.load(core.sync.atomic.Ordering.Relaxed) != 0usize
            } else {
                guard.get().len() < self.chan.get().bound
            }
            if available { break }
            let elapsed = time.now().duration_since(started).as_nanos()
            if elapsed >= timeout_nanos as u128 {
                throw SendTimeoutError(value, true, false)
            }
            let remaining = (timeout_nanos as u128 - elapsed) as u64
            let waited = capture self.chan.get().space.wait_timeout(
                guard, time.from_nanos(remaining)
            )
            let pair = match take waited { success(pair) => pair, failure(e) => e.into_inner() }
            guard = pair.0
        }
        let receipt: Arc<core.sync.atomic.AtomicBool>? = if rendezvous {
            present(alloc.arc.new(core.sync.atomic.AtomicBool.new(false)))
        } else { none }
        let queued_receipt = match receipt {
            present(flag) => present(flag.retain()),
            none => none
        }
        guard.get_mut().push_back(Envelope(value, queued_receipt))
        self.chan.get().ready.notify_one()
        unsafe { mettle_rt_select_notify() }
        if rendezvous {
            while !accepted(read receipt) &&
                  self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
                let elapsed = time.now().duration_since(started).as_nanos()
                if elapsed >= timeout_nanos as u128 {
                    let returned = guard.get_mut().pop_back()
                    self.chan.get().space.notify_all()
                    match take returned {
                        present(unsent) => throw SendTimeoutError(unsent.value, true, false),
                        none => core.intrinsics.abort()
                    }
                }
                let remaining = (timeout_nanos as u128 - elapsed) as u64
                let waited = capture self.chan.get().space.wait_timeout(
                    guard, time.from_nanos(remaining)
                )
                let pair = match take waited { success(pair) => pair, failure(e) => e.into_inner() }
                guard = pair.0
            }
            if !accepted(read receipt) {
                let returned = guard.get_mut().pop_back()
                self.chan.get().space.notify_all()
                match take returned {
                    present(unsent) => throw SendTimeoutError(unsent.value, false, true),
                    none => core.intrinsics.abort()
                }
            }
        }
    }

    pub fn duplicate(): SyncSender<T> {
        let _previous = self.chan.get().senders.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        SyncSender(self.chan.retain())
    }
}

extend<T> Receiver<T> {
    pub fn recv(): T throws RecvError {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        var result: T? = none
        var waiting = true
        while waiting {
            let next = guard.get_mut().pop_front()
            match take next {
                present(envelope) => {
                    result = present(receive(envelope))
                    waiting = false
                    self.chan.get().space.notify_all()
                },
                none => {
                    if self.chan.get().senders.load(core.sync.atomic.Ordering.Acquire) == 0usize {
                        waiting = false
                    } else {
                        let _previous = self.chan.get().waiting_receivers.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
                        self.chan.get().space.notify_one()
                        let waited = capture self.chan.get().ready.wait(guard)
                        guard = match take waited { success(g) => g, failure(e) => e.into_inner() }
                        let _previous = self.chan.get().waiting_receivers.fetch_sub(1usize, core.sync.atomic.Ordering.Relaxed)
                    }
                }
            }
        }
        match take result { present(value) => value, none => throw RecvError() }
    }

    pub fn try_recv(): T throws TryRecvError {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        let next = guard.get_mut().pop_front()
        match take next {
            present(envelope) => {
                let value = receive(envelope)
                self.chan.get().space.notify_all()
                value
            },
            none => throw TryRecvError(self.chan.get().senders.load(core.sync.atomic.Ordering.Acquire) == 0usize)
        }
    }

    // Blocks for at most `timeout_nanos`, unless a message or disconnection wins.
    pub fn recv_timeout(timeout_nanos: u64): T throws RecvTimeoutError {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        let started = time.now()
        var waiting = false
        while guard.get().is_empty() {
            if self.chan.get().senders.load(core.sync.atomic.Ordering.Acquire) == 0usize {
                throw RecvTimeoutError(false, true)
            }
            let elapsed = time.now().duration_since(started).as_nanos()
            if elapsed >= timeout_nanos as u128 {
                throw RecvTimeoutError(true, false)
            }
            if !waiting {
                let _previous = self.chan.get().waiting_receivers.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
                self.chan.get().space.notify_one()
                waiting = true
            }
            let remaining = (timeout_nanos as u128 - elapsed) as u64
            let waited = capture self.chan.get().ready.wait_timeout(
                guard, time.from_nanos(remaining)
            )
            let pair = match take waited { success(pair) => pair, failure(e) => e.into_inner() }
            guard = pair.0
            let _previous = self.chan.get().waiting_receivers.fetch_sub(1usize, core.sync.atomic.Ordering.Relaxed)
            waiting = false
        }
        let next = guard.get_mut().pop_front()
        match take next {
            present(envelope) => {
                let value = receive(envelope)
                self.chan.get().space.notify_all()
                value
            },
            none => core.intrinsics.abort()
        }
    }

    pub fn iter<region r>(
        receiver read self: Receiver<T> from r
    ): Iter<region r, T> {
        Iter(read self)
    }

    pub fn try_iter<region r>(
        receiver read self: Receiver<T> from r
    ): TryIter<region r, T> {
        TryIter(read self, false)
    }

    pub take fn into_iter(): IntoIter<T> { IntoIter(self) }
}

// Blocks until the receiver disconnects, yielding each queued value.
pub type Iter<region r, T> { channel: read Receiver<T> from r }
extend<region r, T> Iter<region r, T> implements Iterator {
    type Item = T
    mut fn next(): T? {
        let value = capture self.channel.recv()
        match take value {
            success(item) => present(item),
            failure(error) => none
        }
    }
}

// Stops when no value is immediately available.
pub type TryIter<region r, T> {
    channel: read Receiver<T> from r
    finished: bool
}
extend<region r, T> TryIter<region r, T> implements Iterator {
    type Item = T
    mut fn next(): T? {
        if self.finished { return none }
        let value = capture self.channel.try_recv()
        match take value {
            success(item) => present(item),
            failure(error) => {
                self.finished = true
                none
            }
        }
    }
}

// Owns the receiver and drains queued values before ending.
pub type IntoIter<T> { channel: Receiver<T> }
extend<T> IntoIter<T> implements Iterator {
    type Item = T
    mut fn next(): T? {
        let value = capture self.channel.recv()
        match take value {
            success(item) => present(item),
            failure(error) => none
        }
    }
}

fn channel_ready<T>(read chan: Shared<T>): bool {
    let locked = capture chan.queue.lock()
    let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    !guard.get().is_empty() ||
        chan.senders.load(core.sync.atomic.Ordering.Acquire) == 0usize ||
        !chan.open.load(core.sync.atomic.Ordering.Acquire)
}

fn register_select_waiter<T>(read chan: Shared<T>): Unit {
    let locked = capture chan.queue.lock()
    let _guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    let _previous = chan.waiting_receivers.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
    chan.space.notify_one()
}

fn unregister_select_waiter<T>(read chan: Shared<T>): Unit {
    let locked = capture chan.queue.lock()
    let _guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    let _previous = chan.waiting_receivers.fetch_sub(1usize, core.sync.atomic.Ordering.Relaxed)
    chan.space.notify_one()
}

extend<T> Receiver<T> implements Iterator {
    type Item = T
    mut fn next(): T? {
        let result = capture self.recv()
        match take result {
            success(value) => present(value),
            failure(error) => none
        }
    }
}

extend<T, region r> read Receiver<T> from r implements Iterator {
    type Item = T
    mut fn next(): T? {
        match take capture self.recv() {
            success(value) => present(value),
            failure(error) => none
        }
    }
}

// Cloning a sender adds another producer, exactly like `duplicate`.
extend<T> Sender<T> implements Clone {
    fn clone(): Sender<T> { self.duplicate() }
}
extend<T> SyncSender<T> implements Clone {
    fn clone(): SyncSender<T> { self.duplicate() }
}
extend<T> Sender<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("Sender { .. }") }
}
extend<T> SyncSender<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("SyncSender { .. }") }
}
extend<T> Receiver<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("Receiver { .. }") }
}

// Borrows a homogeneous receiver set; selecting does not consume its message.
pub type Select<region r, T> {
    receivers: List<read Receiver<T> from r>
    cursor: usize
}

pub fn select<T, region r>(read source: Receiver<T> from r): Select<region r, T> {
    var selected = Select(alloc.vec.new<read Receiver<T> from r>(), 0usize)
    let _first = selected.add(source)
    selected
}

extend<region r, T> Select<region r, T> {
    pub mut fn add(read source: Receiver<T> from r): usize {
        let index = self.receivers.len()
        self.receivers.push(read source)
        index
    }

    pub mut fn select(): usize throws EmptySelect {
        if self.receivers.is_empty() { throw EmptySelect() }
        while true {
            let epoch = unsafe { mettle_rt_select_epoch() }
            var checked = 0usize
            var index = self.cursor
            while checked < self.receivers.len() {
                if channel_ready(self.receivers[index].chan.get()) {
                    self.cursor = if index + 1usize == self.receivers.len() { 0usize } else { index + 1usize }
                    return index
                }
                index = if index + 1usize == self.receivers.len() { 0usize } else { index + 1usize }
                checked += 1usize
            }
            var registered = 0usize
            while registered < self.receivers.len() {
                register_select_waiter(self.receivers[registered].chan.get())
                registered += 1usize
            }
            checked = 0usize
            index = self.cursor
            var chosen: usize? = none
            while checked < self.receivers.len() {
                if channel_ready(self.receivers[index].chan.get()) {
                    chosen = present(index)
                    checked = self.receivers.len()
                } else {
                    index = if index + 1usize == self.receivers.len() { 0usize } else { index + 1usize }
                    checked += 1usize
                }
            }
            match take chosen {
                present(found) => {
                    registered = 0usize
                    while registered < self.receivers.len() {
                        unregister_select_waiter(self.receivers[registered].chan.get())
                        registered += 1usize
                    }
                    self.cursor = if found + 1usize == self.receivers.len() { 0usize } else { found + 1usize }
                    return found
                },
                none => {}
            }
            unsafe { mettle_rt_select_wait(epoch) }
            registered = 0usize
            while registered < self.receivers.len() {
                unregister_select_waiter(self.receivers[registered].chan.get())
                registered += 1usize
            }
        }
    }
}
