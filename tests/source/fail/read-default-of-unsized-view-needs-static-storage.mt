// expect-error: type 2:15 incompatible aggregate shape
fn total(read items: [i32] = [1, 2, 3]): i32 { items[0] }

fn main(): i32 { total() }
