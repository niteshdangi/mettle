// profiles: debug release
// expect-error: constant 8:14 constant write requires exclusive access
// expect-error-count: 1

const fn forbidden_write(): i32 {
    var value = 7i32
    let pointer = core.ptr.from_ref(read value) as ptr<mut i32>
    unsafe { *pointer = 9i32 }
    value
}

const VALUE: i32 = forbidden_write()
fn main(): i32 { VALUE }
