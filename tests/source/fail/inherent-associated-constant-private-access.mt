// expect-error: name 9:21 unresolved or inaccessible name
pub module inner {
    pub type Grid {}
    extend Grid {
        const SIDE: usize = 3usize
    }
}
fn main() {
    let count: [u8; inner.Grid.SIDE] = [0u8; 3usize]
    0
}
