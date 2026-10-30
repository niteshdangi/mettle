
enum Slot<K, V> { Empty, Full(K, V) }
type M<K, V> { slots: Slot<K, V> }
impl<K, V> M<K, V> {
    fn full(): i32 { match self.slots { Slot::Full(_, v) => 1, _ => 0 } }
}
fn main(): i32 { 0 }
