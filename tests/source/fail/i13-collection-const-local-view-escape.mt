// profiles: debug release
// expect-error: constant 9:30 constant pointer is dangling
// expect-error-count: 1
const fn escaping(): read [i32; 1] from static {
    let values = [1i32]
    read values
}

static LEAK: read [i32; 1] = escaping()
