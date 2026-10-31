// ThreadId and Thread: equality, hashing and cloning.
import core.hash.hash_one
import core.clone.Clone
import std.thread

fn main(): i32 {
    let me = thread.current()
    if me.id() != thread.current().id() || me.clone().id() != me.id() { return 1 }
    if hash_one(read me.id()) != hash_one(read thread.current().id()) { return 2 }
    let other = thread.spawn(take fn(): thread.ThreadId { thread.current().id() })
    let joined = capture other.join()
    match take joined {
        success(id) => { if id == me.id() { return 4 } },
        failure(_) => { return 3 }
    }
    0
}
