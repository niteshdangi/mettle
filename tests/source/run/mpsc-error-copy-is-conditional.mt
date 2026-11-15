fn require_copy<T: Copy>() {}

fn main(): i32 {
    require_copy<std.sync.mpsc.SendError<i32>>()
    require_copy<std.sync.mpsc.TrySendError<i32>>()
    0
}
