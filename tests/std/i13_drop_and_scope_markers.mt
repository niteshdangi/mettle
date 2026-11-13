import alloc.rc
import std.io
import std.io.{Error, Writer}
import std.thread

type Counted<region r> { writes: read core.sync.atomic.AtomicUsize from r; flushes: read core.sync.atomic.AtomicUsize from r }
extend<region r> Counted<region r> implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error {
        let _ = self.writes.fetch_add(bytes.len(), core.sync.atomic.Ordering.SeqCst)
        bytes.len()
    }
    mut fn flush(): Unit throws Error {
        let _ = self.flushes.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

fn requires_send<T: unsized + Transferable>(read value: T): Unit {}
fn requires_sync<T: unsized + Shareable>(read value: T): Unit {}

fn run(): i32 throws Error {
    let writes = core.sync.atomic.AtomicUsize.new(0usize)
    let flushes = core.sync.atomic.AtomicUsize.new(0usize)
    {
        var buffered = io.buf_writer(Counted(read writes, read flushes))
        try buffered.write_all("kept".as_bytes())
        if writes.load(core.sync.atomic.Ordering.SeqCst) != 0usize { return 1 }
    }
    if writes.load(core.sync.atomic.Ordering.SeqCst) != 4usize || flushes.load(core.sync.atomic.Ordering.SeqCst) != 0usize { return 2 }

    let strong = rc.new(5)
    {
        let observer = strong.downgrade()
        if strong.weak_count() != 1usize { return 3 }
    }
    if strong.weak_count() != 0usize { return 4 }

    thread.scope(fn(read scope: thread.Scope): Unit {
        requires_send(scope)
        requires_sync(scope)
        let child = scope.spawn(fn(): i32 { 1 })
        requires_send(child)
        requires_sync(child)
    })
    0
}

fn main(): i32 {
    match capture run() {
        success(code) => code,
        failure(error) => 99
    }
}
