module core {
    pub module ops {
        pub interface FnPtr: Copy {}
    }
    pub module ptr {
        pub type NonNull<T: unsized> { pub pointer: ptr<mut T> }
    }
}

interface Category { fn category(): i32; }
extend<F: core.ops.FnPtr> F implements Category {
    fn category(): i32 { 1 }
}
extend<T: unsized> ptr<read T> implements Category {
    fn category(): i32 { 2 }
}
extend<T: unsized> ptr<mut T> implements Category {
    fn category(): i32 { 3 }
}
extend<region r, T: unsized> read T from r implements Category {
    fn category(): i32 { 4 }
}
extend<region r, T: unsized> mut T from r implements Category {
    fn category(): i32 { 5 }
}
extend<T: unsized> core.ptr.NonNull<T> implements Category {
    fn category(): i32 { 6 }
}
extend<T> [T] implements Category {
    fn category(): i32 { 7 }
}

fn identity(value: i32): i32 { value }
fn classify<T: Category>(read value: T): i32 { value.category() }

fn main(): i32 {
    let function: fn(i32): i32 = identity
    if classify(read function) != 1 { return 1 }
    if function(7) != 7 { return 2 }
    0
}
