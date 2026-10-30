// expect-error: type 6:5 cannot be called through the interface name
interface Plain { fn plain(): i32; }
impl i32 implements Plain { fn plain(): i32 { self } }
fn main(): i32 {
    let x: i32 = 5
    Plain::plain(x) - 5
}
