interface Measure {
    fn size(): usize
}
type Pair { left: i32; right: i32 }
extend Pair
    implements Measure {
    fn size(): usize { 2usize }
}
extend Pair {
    pub fn pick<U>(choice: U): U
        where U: Copy { choice }
    pub unsafe static fn trusted(left: i32, right: i32): Pair { Pair(left, right) }
    unsafe mut fn swap_halves(): Unit {
        let old = self.left
        self.left = self.right
        self.right = old
    }
}
fn main(): i32 {
    var pair = unsafe { Pair.trusted(1, 2) }
    if pair.size() != 2usize || pair.pick(7) != 7 { return 1 }
    unsafe { pair.swap_halves() }
    if pair.left != 2 || pair.right != 1 { return 2 }
    0
}
