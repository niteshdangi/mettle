// expect-error: name 5:5 private or restricted field 'raw' is inaccessible
import std.sync.mutex
fn main(): i32 {
    var lock = mutex.new(0)
    lock.raw = core.ptr.null_mut<u8>()
    0
}
