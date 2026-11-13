// expect-error: ownership 7:26 access or storage conflicts
import std.thread

fn main(): i32 {
    let handle = thread.spawn(take fn(): i32 { 0 })
    let worker = handle.thread()
    let joined = capture handle.join()
    let _ = worker.id()
    match take joined { success(value) => value, failure(_) => 1 }
}
