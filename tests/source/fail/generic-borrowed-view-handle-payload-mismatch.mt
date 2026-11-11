// expect-error: type 7:18 invariant payload type
fn inspect<T>(mut view: read [T]): usize { view.len() }

fn main(): i32 {
    let values = [10i32, 20i32]
    var view: read [i32] = read values[..]
    inspect<i64>(mut view)
    0
}
