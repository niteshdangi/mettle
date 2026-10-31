import std.thread
import std.sync.barrier
import alloc.arc

fn main(): i32 {
    var config = thread.Builder.new()
    config.name("configured worker")
    config.stack_size(1048576usize)
    let gate = arc.new(barrier.new(2usize))
    let worker_gate = gate.retain()
    let handle = config.spawn(take fn(): i32 {
        worker_gate.get().wait()
        17
    })
    if handle.id().raw == 0usize { return 1 }
    if handle.is_finished() { return 2 }
    gate.get().wait()
    let result = capture handle.join()
    match take result {
        success(value) => { if value != 17 { return 3 } },
        failure(error) => { return 4 }
    }
    let borrowed = 23
    let scoped_gate = arc.new(barrier.new(2usize))
    let scoped_worker_gate = scoped_gate.retain()
    let scoped = thread.scope(fn(scope: read thread.Scope): i32 {
        var scoped_config = thread.Builder.new()
        scoped_config.name("scoped worker")
        scoped_config.stack_size(1048576usize)
        let child = scoped_config.spawn_scoped(scope, fn(): i32 {
            scoped_worker_gate.get().wait()
            borrowed
        })
        if child.is_finished() { return -1 }
        scoped_gate.get().wait()
        let result = capture child.join()
        match take result {
            success(value) => value,
            failure(error) => -1
        }
    })
    if scoped != 23 { return 5 }

    var invalid = thread.Builder.new()
    invalid.stack_size(1usize)
    let failed = capture invalid.spawn(take fn(): i32 { 0 })
    match take failed {
        success(handle) => { return 6 },
        failure(error) => { if error.code == 0 { return 7 } }
    }
    0
}
