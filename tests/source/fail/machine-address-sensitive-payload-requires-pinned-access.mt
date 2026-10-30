// expect-error: type 6:21 invalid primitive operation

type Stable { marker: core::marker::PhantomPinned; value: i32 }
fn main() {
    var handle = core::pin::pin(Stable(core::marker::PhantomPinned,42))
    let reference = handle.get_mut()
    0
}
