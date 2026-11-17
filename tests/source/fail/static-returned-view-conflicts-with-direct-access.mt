// expect-error: ownership 10:31 access or storage conflicts with a live exclusive loan
// expect-error: ownership 11:5 access or storage conflicts with a live read loan
static mut VALUE: i32 = 1

fn first(): mut i32 from static { unsafe { mut VALUE } }
fn second(): mut i32 from static { first() }

fn main(): i32 {
    let view = second()
    let other = unsafe { read VALUE }
    *view = 42
    *other
}
