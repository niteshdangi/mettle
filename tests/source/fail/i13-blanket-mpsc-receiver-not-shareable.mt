// expect-error: type 6:5 unsatisfied interface bound 'Shareable'
// std.sync.mpsc.Receiver is a negative impl (Rust: impl !Sync), so a Sync row cannot hold.
fn sync_ok<T: Shareable>(): Unit {}
alias Channel = std.sync.mpsc.Receiver<i32>
fn main(): i32 {
    sync_ok<Channel>()
    0
}
