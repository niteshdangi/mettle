interface Family {
    type Item: Thin
}

fn null_for<T: unsized + Thin>(): ptr<read T> {
    core.ptr.null<T>()
}

fn null_for_equal<T: unsized, U: unsized + Thin>(): ptr<read T>
where T = U {
    core.ptr.null<T>()
}

fn null_for_item<T: Family>(): ptr<read T.(Family).Item> {
    core.ptr.null<T.(Family).Item>()
}

fn main(): i32 {
    if null_for<i32>().is_null() &&
       null_for_equal<i32, i32>().is_null() { 0 } else { 1 }
}
