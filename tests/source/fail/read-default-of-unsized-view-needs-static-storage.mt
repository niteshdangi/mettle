// expect-error: type 2:15 default of a borrowed unsized parameter must be a literal or a view of static storage; an array literal is not static
fn total(read items: [i32] = [1, 2, 3]): i32 { items[0] }

fn main(): i32 { total() }
