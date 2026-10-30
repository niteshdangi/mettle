import super::mutex;
import super::condvar;
import package::alloc::arc::Arc;
import package::alloc::vec_deque::VecDeque;
import package::core::clone::Clone;

// Shared by every endpoint. Messages are queued under the lock; `ready` wakes
// a blocked receiver when a message arrives or the last sender goes away.
type Shared<T> {
    queue: mutex::Mutex<VecDeque<T>>
    ready: condvar::Condvar
    // Wakes senders blocked on a full bounded queue.
    space: condvar::Condvar
    bound: usize
    senders: core::sync::atomic::AtomicUsize
    open: core::sync::atomic::AtomicBool
}

// The receiver is gone; the unsent value is handed back.
pub type SendError<T> { pub value: T }
// Every sender is gone and the queue is empty.
pub copy type RecvError {}
pub copy type TryRecvError { pub disconnected: bool }
// A non-blocking send failed: the queue is full or the receiver is gone.
pub type TrySendError<T> { pub value: T; pub disconnected: bool }

pub type Sender<T> {
    chan: Arc<Shared<T>>
    drop {
        if self.chan.get().senders.fetch_sub(1usize, core::sync::atomic::Ordering::AcqRel) == 1usize {
            self.chan.get().ready.notify_all()
        }
    }
}
pub type Receiver<T> {
    chan: Arc<Shared<T>>
    drop {
        self.chan.get().open.store(false, core::sync::atomic::Ordering::Release)
        self.chan.get().space.notify_all()
    }
}
impl<T> Receiver<T> not Shareable;

// Sending half of a bounded channel; `send` blocks while the queue is full.
pub type SyncSender<T> {
    chan: Arc<Shared<T>>
    drop {
        if self.chan.get().senders.fetch_sub(1usize, core::sync::atomic::Ordering::AcqRel) == 1usize {
            self.chan.get().ready.notify_all()
        }
    }
}

fn new_shared<T>(bound: usize): Arc<Shared<T>> {
    package::alloc::arc::new(Shared(mutex::new(package::alloc::vec_deque::new::<T>()), condvar::new(), condvar::new(), bound, core::sync::atomic::AtomicUsize::new(1usize), core::sync::atomic::AtomicBool::new(true)))
}

pub fn channel<T>(): (Sender<T>, Receiver<T>) {
    let chan = new_shared::<T>(0usize)
    let other = chan.retain()
    (Sender(chan), Receiver(other))
}

// A channel holding at most `bound` queued messages (a bound of 0 is
// treated as 1, there is no rendezvous mode).
pub fn sync_channel<T>(bound: usize): (SyncSender<T>, Receiver<T>) {
    let chan = new_shared::<T>(if bound == 0usize { 1usize } else { bound })
    let other = chan.retain()
    (SyncSender(chan), Receiver(other))
}

impl<T> Sender<T> {
    pub fn send(value: take T): Unit throws SendError<T> {
        if !self.chan.get().open.load(core::sync::atomic::Ordering::Acquire) { throw SendError(value) }
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        guard.get_mut().push_back(value)
        self.chan.get().ready.notify_one()
    }
    pub fn duplicate(): Sender<T> {
        self.chan.get().senders.fetch_add(1usize, core::sync::atomic::Ordering::Relaxed)
        Sender(self.chan.retain())
    }
}

impl<T> SyncSender<T> {
    // Blocks while the queue is full; fails if the receiver goes away.
    pub fn send(value: take T): Unit throws SendError<T> {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        while guard.get().len() >= self.chan.get().bound && self.chan.get().open.load(core::sync::atomic::Ordering::Acquire) {
            guard = self.chan.get().space.wait(guard)
        }
        if !self.chan.get().open.load(core::sync::atomic::Ordering::Acquire) { throw SendError(value) }
        guard.get_mut().push_back(value)
        self.chan.get().ready.notify_one()
    }
    pub fn try_send(value: take T): Unit throws TrySendError<T> {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        if !self.chan.get().open.load(core::sync::atomic::Ordering::Acquire) { throw TrySendError(value, true) }
        if guard.get().len() >= self.chan.get().bound { throw TrySendError(value, false) }
        guard.get_mut().push_back(value)
        self.chan.get().ready.notify_one()
    }
    pub fn duplicate(): SyncSender<T> {
        self.chan.get().senders.fetch_add(1usize, core::sync::atomic::Ordering::Relaxed)
        SyncSender(self.chan.retain())
    }
}

impl<T> Receiver<T> {
    // Blocks for the next message; fails once all senders are gone and the
    // queue is drained.
    pub fn recv(): T throws RecvError {
        let locked = capture self.chan.get().queue.lock()
        var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
        var result: T? = none
        var waiting = true
        while waiting {
            let next = guard.get_mut().pop_front()
            match take next {
                present(value) => { result = present(value); waiting = false; self.chan.get().space.notify_one() },
                none => {
                    if self.chan.get().senders.load(core::sync::atomic::Ordering::Acquire) == 0usize { waiting = false } else { guard = self.chan.get().ready.wait(guard) }
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
            present(value) => { self.chan.get().space.notify_one(); value },
            none => throw TryRecvError(self.chan.get().senders.load(core::sync::atomic::Ordering::Acquire) == 0usize)
        }
    }
}
