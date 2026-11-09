import std.thread
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
    let handle = thread.spawn(take fn(): usize {
        thread.current().raw
    })
    require_debug(handle, "JoinHandle")
    let worker = handle.thread()
    let cloned_worker = worker.clone()
    let worker_id = worker.id()
    let cloned_id = worker_id.clone()

    if cloned_worker.id() != worker_id || cloned_id != worker_id { return 1 }
    if hash_one(read cloned_id) != hash_one(read worker_id) { return 2 }
    require_debug(worker, "Thread")
    require_debug(worker_id, "ThreadId")

    let joined = capture handle.join()
    match take joined {
        success(id) => { if id != worker_id.raw { return 3 } },
        failure(error) => { return 4 }
    }

    let scoped = thread.scope(fn(read scope: thread.Scope): i32 {
        require_debug(scope, "Scope")
        let child = scope.spawn(fn(): usize {
            thread.current().raw
        })
        require_debug(child, "ScopedJoinHandle")
        let child_id = child.thread().id()
        if child_id.raw == thread.current().raw { return 5 }

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
