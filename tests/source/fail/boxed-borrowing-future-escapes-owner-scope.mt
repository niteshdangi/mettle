// expect-error: ownership 8:5 access or storage conflicts with a live read loan
type Fixed { base: i32; drop {} }
extend Fixed { async fn total(n: i32): i32 { self.base + n } }
fn main(): i32 {
    let h = {
        let f = Fixed(1)
        alloc.boxed.new(f.total(2))
    }
    let k = h
    0
}
