// expect-error: type 5:5 for requires a concrete range or array
import core.iter.Iterator

fn main(): i32 {
    for value in ..5 { }
    0
}
