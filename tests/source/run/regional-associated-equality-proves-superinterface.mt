interface Items { type Item; }
interface Backward: Items {}
type Mapped<region r, T, I: Items<Item = read T from r>> { inner: I; witness: read T from r }
extend<region r, T, I: Items<Item = read T from r>> Mapped<region r, T, I> implements Items { type Item = T; }
extend<region r, T, I: Backward + Items<Item = read T from r>> Mapped<region r, T, I> implements Backward {}
fn main(): i32 { 0 }
