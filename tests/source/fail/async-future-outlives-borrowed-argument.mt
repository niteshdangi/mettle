// expect-error: ownership 10:5 access or storage lifetime conflicts with a live read loan
type Counter { value: i32 }
fn sync_plain(c: read Counter): i32 { c.value }
async fn a(value: read Counter): i32 { sync_plain(value) }
fn consume<T>(value: take T) {}
fn main(): i32 {
    let fut = {
        let c = Counter(1)
        a(read c)
    }
    consume(fut)
    0
}
