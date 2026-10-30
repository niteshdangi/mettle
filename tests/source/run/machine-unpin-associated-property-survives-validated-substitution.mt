
interface Family { type Item: Unpin; }
type Maker {}
impl Maker implements Family { type Item = i32; }
fn access<T: Family>(value: mut <T implements Family>::Item): mut <T implements Family>::Item from value {
    var handle = core::pin::Pin::new(mut value)
    handle.into_inner()
}
fn main() {
    var value = 41
    *access::<Maker>(value) += 1
    if value == 42 { 0 } else { 1 }
}
