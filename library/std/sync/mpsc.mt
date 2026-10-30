import super.mutex;
import super.condvar;
import super.super.time;
import package.alloc.arc.Arc;
import package.alloc.vec.List;
import package.alloc.vec_deque.Deque;
import package.core.iter.Iterator;

extern "C" {
    unsafe fn mettle_rt_select_epoch(): u64;
    unsafe fn mettle_rt_select_wait(epoch: u64): Unit;
    unsafe fn mettle_rt_select_notify(): Unit;
}

type Shared<T> {
    queue: mutex.Mutex<Deque<T>>
    ready: condvar.Condvar
    space: condvar.Condvar
    bound: usize
    waiting_receivers: core.sync.atomic.AtomicUsize
    senders: core.sync.atomic.AtomicUsize
    open: core.sync.atomic.AtomicBool
}

pub type SendError<T> { pub value: T }
pub copy type RecvError {}
pub copy type TryRecvError { pub disconnected: bool }
pub type TrySendError<T> { pub value: T; pub disconnected: bool }
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
        let locked = capture self.chan.get().queue.lock()
        let _guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        self.chan.get().open.store(false, core.sync.atomic.Ordering.Release)
        self.chan.get().ready.notify_all()
        self.chan.get().space.notify_all()
        unsafe { mettle_rt_select_notify() }
    }
}
extend<T> Receiver<T> not Shareable;

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

fn new_shared<T>(bound: usize): Arc<Shared<T>> {
    package.alloc.arc.new(Shared(
        mutex.new(package.alloc.vec_deque.new<T>()),
        condvar.new(),
        condvar.new(),
        bound,
        core.sync.atomic.AtomicUsize.new(0usize),
        core.sync.atomic.AtomicUsize.new(1usize),
        core.sync.atomic.AtomicBool.new(true)
    ))
}

pub fn channel<T>(): (Sender<T>, Receiver<T>) {
    let chan = new_shared<T>(0usize)
    let other = chan.retain()
    (Sender(chan), Receiver(other))
}

// A zero bound is a rendezvous: send returns only after a receiver takes the
// message.
pub fn sync_channel<T>(bound: usize): (SyncSender<T>, Receiver<T>) {
    let chan = new_shared<T>(bound)
    let other = chan.retain()
    (SyncSender(chan), Receiver(other))
}

extend<T> Sender<T> {
    pub fn send(value: take T): Unit throws SendError<T> {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if !self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
            throw SendError(value)
        }
        guard.get_mut().push_back(value)
        self.chan.get().ready.notify_one()
        unsafe { mettle_rt_select_notify() }
    }

    pub fn try_send(value: take T): Unit throws TrySendError<T> {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if !self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
            throw TrySendError(value, true)
        }
        guard.get_mut().push_back(value)
        self.chan.get().ready.notify_one()
        unsafe { mettle_rt_select_notify() }
    }

    pub fn duplicate(): Sender<T> {
        let _previous = self.chan.get().senders.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
        Sender(self.chan.retain())
    }
}

extend<T> SyncSender<T> {
    pub fn send(value: take T): Unit throws SendError<T> {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        let rendezvous = self.chan.get().bound == 0usize
        while self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) &&
              (if rendezvous {
                  !guard.get().is_empty() || self.chan.get().waiting_receivers.load(core.sync.atomic.Ordering.Relaxed) == 0usize
              } else {
                  guard.get().len() >= self.chan.get().bound
              }) {
            guard = self.chan.get().space.wait(guard)
        }
        if !self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
            throw SendError(value)
        }
        guard.get_mut().push_back(value)
        self.chan.get().ready.notify_one()
        unsafe { mettle_rt_select_notify() }
        if rendezvous {
            while !guard.get().is_empty() &&
                  self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
                guard = self.chan.get().space.wait(guard)
            }
            if !guard.get().is_empty() {
                let returned = guard.get_mut().pop_back()
                self.chan.get().space.notify_all()
                match take returned {
                    present(unsent) => throw SendError(unsent),
                    none => core.intrinsics.abort()
                }
            }
        }
    }

    pub fn try_send(value: take T): Unit throws TrySendError<T> {
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
        guard.get_mut().push_back(value)
        self.chan.get().ready.notify_one()
        unsafe { mettle_rt_select_notify() }
    }

    // Blocks for at most `timeout_nanos`, returning the value if not accepted.
    pub fn send_timeout(value: take T, timeout_nanos: u64): Unit throws SendTimeoutError<T> {
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
            let waited = self.chan.get().space.wait_timeout(guard, remaining)
            guard = waited.0
        }
        guard.get_mut().push_back(value)
        self.chan.get().ready.notify_one()
        unsafe { mettle_rt_select_notify() }
        if rendezvous {
            while !guard.get().is_empty() &&
                  self.chan.get().open.load(core.sync.atomic.Ordering.Acquire) {
                let elapsed = time.now().duration_since(started).as_nanos()
                if elapsed >= timeout_nanos as u128 {
                    let returned = guard.get_mut().pop_back()
                    self.chan.get().space.notify_all()
                    match take returned {
                        present(unsent) => throw SendTimeoutError(unsent, true, false),
                        none => core.intrinsics.abort()
                    }
                }
                let remaining = (timeout_nanos as u128 - elapsed) as u64
                let waited = self.chan.get().space.wait_timeout(guard, remaining)
                guard = waited.0
            }
            if !guard.get().is_empty() {
                let returned = guard.get_mut().pop_back()
                self.chan.get().space.notify_all()
                match take returned {
                    present(unsent) => throw SendTimeoutError(unsent, false, true),
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
                present(value) => {
                    result = present(value)
                    waiting = false
                    self.chan.get().space.notify_all()
                },
                none => {
                    if self.chan.get().senders.load(core.sync.atomic.Ordering.Acquire) == 0usize {
                        waiting = false
                    } else {
                        let _previous = self.chan.get().waiting_receivers.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
                        self.chan.get().space.notify_one()
                        guard = self.chan.get().ready.wait(guard)
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
            present(value) => { self.chan.get().space.notify_all(); value },
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
            let waited = self.chan.get().ready.wait_timeout(guard, remaining)
            guard = waited.0
            let _previous = self.chan.get().waiting_receivers.fetch_sub(1usize, core.sync.atomic.Ordering.Relaxed)
            waiting = false
        }
        let next = guard.get_mut().pop_front()
        match take next {
            present(value) => { self.chan.get().space.notify_all(); value },
            none => core.intrinsics.abort()
        }
    }
}

fn channel_ready<T>(chan: read Shared<T>): bool {
    let locked = capture chan.queue.lock()
    let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    !guard.get().is_empty() ||
        chan.senders.load(core.sync.atomic.Ordering.Acquire) == 0usize ||
        !chan.open.load(core.sync.atomic.Ordering.Acquire)
}

fn register_select_waiter<T>(chan: read Shared<T>): Unit {
    let locked = capture chan.queue.lock()
    let _guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    let _previous = chan.waiting_receivers.fetch_add(1usize, core.sync.atomic.Ordering.Relaxed)
    chan.space.notify_one()
}

fn unregister_select_waiter<T>(chan: read Shared<T>): Unit {
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

// Borrows a homogeneous receiver set; selecting does not consume its message.
pub type Select<region r, T> {
    receivers: List<read Receiver<T> from r>
    cursor: usize
}

pub fn select<T, region r>(source: read Receiver<T> from r): Select<region r, T> {
    var selected = Select(package.alloc.vec.new<read Receiver<T> from r>(), 0usize)
    let _first = selected.add(source)
    selected
}

extend<region r, T> Select<region r, T> {
    pub mut fn add(source: read Receiver<T> from r): usize {
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
                if channel_ready(self.receivers.as_slice()[index].chan.get()) {
                    self.cursor = if index + 1usize == self.receivers.len() { 0usize } else { index + 1usize }
                    return index
                }
                index = if index + 1usize == self.receivers.len() { 0usize } else { index + 1usize }
                checked += 1usize
            }
            var registered = 0usize
            while registered < self.receivers.len() {
                register_select_waiter(self.receivers.as_slice()[registered].chan.get())
                registered += 1usize
            }
            checked = 0usize
            index = self.cursor
            var chosen: usize? = none
            while checked < self.receivers.len() {
                if channel_ready(self.receivers.as_slice()[index].chan.get()) {
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
                        unregister_select_waiter(self.receivers.as_slice()[registered].chan.get())
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
                unregister_select_waiter(self.receivers.as_slice()[registered].chan.get())
                registered += 1usize
            }
        }
    }
}
