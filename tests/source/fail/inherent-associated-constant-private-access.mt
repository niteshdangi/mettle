// expect-error: name 9:21 unresolved or inaccessible name
pub module internal {
    pub type Grid {}
    impl Grid {
        const SIDE: usize = 3usize
    }
}
fn main() {
    let count: [u8; internal::Grid::SIDE] = [0u8; 3usize]
    0
}
