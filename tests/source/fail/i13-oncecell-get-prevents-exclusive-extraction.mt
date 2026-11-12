// expect-error: ownership 6:13 access or storage lifetime conflicts with a live read loan
import core.cell.OnceCell
fn main(): i32 {
    var cell = OnceCell<i32>.new()
    let held = cell.get_or_init(fn(): i32 { 42 })
    let _ = cell.`take`()
    *held
}
