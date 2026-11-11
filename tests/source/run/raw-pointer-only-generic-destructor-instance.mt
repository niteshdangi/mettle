type Guard<T> { value: T; drop {} }

unsafe fn destroy(p: ptr<mut Guard<i32>>): Unit {
    core.ptr.drop_in_place(p)
}

fn main(): i32 { 0 }
