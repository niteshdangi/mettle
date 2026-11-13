// expect-error: ownership 10:17 access or storage conflicts
import std.sync.mutex

fn main(): i32 {
    let owner = mutex.new([1, 2])
    let lock: read mutex.Mutex<[i32]> = read owner
    let locked = capture lock.lock()
    let guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    let _before = guard.get().len()
    let moved = owner
    guard.get()[0usize]
}
