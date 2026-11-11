// expect-error: type 6:1 interface arguments do not satisfy their declared constraints
interface Items { type Item; }
interface Backward: Items {}
type Mapped<region r, T, I> { inner: I; witness: read T from r }
extend<region r, T, I: Items<Item = read T from r>> Mapped<region r, T, I> implements Items { type Item = T; }
extend<region r, region s, T, I: Backward + Items<Item = read T from s>> Mapped<region r, T, I> implements Backward {}
fn main(): i32 { 0 }
