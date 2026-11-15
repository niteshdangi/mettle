import std.clone.Clone
import std.cmp.{Ordering, min_by}
import std.convert.{Infallible, identity}
import std.ops.{Bound, Range, RangeBounds}

fn main(): i32 {
    let value = identity(3i32)
    if value.clone() != 3 { return 1 }

    let converted: Outcome<i32, Infallible> = success(value)
    if converted != success(3i32) { return 2 }

    let bound = Bound.Included(3i32)
    if bound != Bound.Included(3i32) { return 3 }

    let range = Range(2i32, 5i32)
    if !range.contains(read 3) { return 4 }

    let smaller = min_by(
        4i32,
        2i32,
        fn(read left: i32, read right: i32): Ordering {
            if left < right { Ordering.Less } else if left == right { Ordering.Equal } else { Ordering.Greater }
        }
    )
    if smaller != 2 { return 5 }
    0
}
