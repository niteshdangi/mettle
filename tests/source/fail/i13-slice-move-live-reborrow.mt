// expect-error: ownership 6:24 live exclusive loan
fn invalid_move_parent(): usize {
    var data = [1u8, 2u8]
    var parent = mut data[..]
    let child = parent.split_at_mut(1usize).0
    core.mem.drop(take parent)
    child.len()
}

fn main(): i32 { 0 }
