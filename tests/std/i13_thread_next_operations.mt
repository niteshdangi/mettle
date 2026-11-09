import std.thread
import alloc.arc
import core.clone.Clone
import core.fmt.Debug
import core.fmt
import core.hash.hash_one

fn require_debug<T: Debug>(read value: T, read prefix: core.text.Text): Unit {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { panic("thread debug formatting failed") }
        }
    }
    assert(output.as_text().starts_with(read prefix), "thread debug writes its type")
}

fn main(): i32 {
    let finished_gate = arc.new(core.sync.atomic.AtomicBool.new(false))
    let worker_gate = finished_gate.retain()
    let handle = thread.spawn(take fn(): usize {
        while !worker_gate.get().load(core.sync.atomic.Ordering.Acquire) {
            thread.yield_now()
        }
        thread.current().raw
    })
    require_debug(handle, "JoinHandle")
    if handle.is_finished() { return 8 }
    let worker = handle.thread()
    let cloned_worker = worker.clone()
    let worker_id = worker.id()
    let cloned_id = worker_id.clone()

    if cloned_worker.id() != worker_id || cloned_id != worker_id { return 1 }
    if hash_one(read cloned_id) != hash_one(read worker_id) { return 2 }
    require_debug(worker, "Thread")
    require_debug(worker_id, "ThreadId")
    finished_gate.get().store(true, core.sync.atomic.Ordering.Release)
    while !handle.is_finished() { thread.yield_now() }

    let joined = capture handle.join()
    match take joined {
        success(id) => { if id != worker_id.raw { return 3 } },
        failure(error) => { return 4 }
    }

    let scoped_gate = arc.new(core.sync.atomic.AtomicBool.new(false))
    let scoped_worker_gate = scoped_gate.retain()
    let scoped = thread.scope(fn(read scope: thread.Scope): i32 {
        require_debug(scope, "Scope")
        let child = scope.spawn(fn(): usize {
            while !scoped_worker_gate.get().load(core.sync.atomic.Ordering.Acquire) {
                thread.yield_now()
            }
            thread.current().raw
        })
        require_debug(child, "ScopedJoinHandle")
        if child.is_finished() { return 9 }
        let child_id = child.thread().id()
        if child_id.raw == thread.current().raw { return 5 }
        scoped_gate.get().store(true, core.sync.atomic.Ordering.Release)
        while !child.is_finished() { thread.yield_now() }

        let joined = capture child.join()
        match take joined {
            success(id) => { if id != child_id.raw { return 6 } },
            failure(error) => { return 7 }
        }
        0
    })
    if scoped != 0 { return scoped }
    0
}
