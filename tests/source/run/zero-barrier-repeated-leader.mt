import std.sync.barrier

fn main(): i32 {
    let zero = barrier.new(0usize)
    if !zero.wait().is_leader() || !zero.wait().is_leader() { return 1 }
    0
}
