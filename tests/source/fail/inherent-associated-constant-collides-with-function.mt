// expect-error: name 4:5 duplicate associated item
type Grid {}
extend Grid {
    const selected: i32 = 1
    static fn selected(): i32 { 0 }
}
fn main() { 0 }
