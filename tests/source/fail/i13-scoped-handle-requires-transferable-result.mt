// expect-error: type 6:5 unsatisfied interface bound 'Shareable'
import std.thread

fn share<T: Shareable>(read value: T): Unit {}
fn check(read handle: thread.ScopedJoinHandle<alloc.rc.LocalShared<i32>>): Unit {
    share(handle)
}
fn main(): i32 { 0 }
