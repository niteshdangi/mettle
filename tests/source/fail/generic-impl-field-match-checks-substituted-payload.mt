// expect-error: type 6:40 expected i32, found V

enum Slot<K, V> { Empty, Full(K, V) }
type M<K, V> { slots: Slot<K, V> }
impl<K, V> M<K, V> {
    fn bad(): i32 { match self.slots { Slot::Full(_, v) => v, _ => 0 } }
}
fn main(): i32 { 0 }
