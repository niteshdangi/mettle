import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import std.ffi.{os_str_from_text, os_string_from_text}
import std.path.{path_buf_from_text, path_from_text}

fn ordered<T: Ord + Eq + PartialOrd + PartialEq + unsized>(read low: T, read same: T, read high: T): bool {
    T.(PartialEq).eq(low, same) && T.(PartialEq).ne(low, high) &&
        T.(PartialOrd).lt(low, high) && T.(PartialOrd).ge(high, low) &&
        T.(Ord).cmp(low, high) == Ordering.Less &&
        T.(Ord).cmp(high, low) == Ordering.Greater &&
        T.(Ord).cmp(low, same) == Ordering.Equal &&
        T.(PartialOrd).partial_cmp(low, high) == present(Ordering.Less)
}

fn main(): i32 {
    if !ordered(path_from_text("/a"), path_from_text("/a"), path_from_text("/b")) { return 1 }
    if !ordered(path_buf_from_text("/a"), path_buf_from_text("/a"), path_buf_from_text("/b")) { return 2 }
    if !ordered(os_str_from_text("a"), os_str_from_text("a"), os_str_from_text("b")) { return 3 }
    if !ordered(os_string_from_text("a"), os_string_from_text("a"), os_string_from_text("b")) { return 4 }
    0
}
