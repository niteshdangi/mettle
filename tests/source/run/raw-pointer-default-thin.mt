import core.default.Default
import core.ptr

fn default_mut<T: unsized + Thin>(): ptr<mut T> {
    ptr<mut T>.(Default).default()
}

fn main(): i32 {
    let mutable = default_mut<i32>()
    let immutable: ptr<read i32> = ptr<read i32>.(Default).default()
    if mutable.is_null() && immutable.is_null() { 0 } else { 1 }
}
