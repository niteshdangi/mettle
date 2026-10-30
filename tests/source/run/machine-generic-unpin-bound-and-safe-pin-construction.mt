
fn access<T: Unpin>(value: mut pinned mut T): mut T from value {
    value.get_mut()
}
fn main() {
    var value = 41
    {
        var handle = core::pin::Pin::new(mut value)
        let view = access(handle)
        *view += 1
    }
    if value == 42 { 0 } else { 1 }
}
