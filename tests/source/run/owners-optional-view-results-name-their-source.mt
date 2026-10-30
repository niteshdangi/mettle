
type Table<K, V> { vs: ptr<mut V>; n: usize; k: Option2<K> }
type Option2<K> { k: K }
extend<K, V> Table<K, V> {
    fn get(k: read K, i: usize): (read V from self)? {
        if i < self.n { present(unsafe { read *self.vs.add(i) }) } else { none }
    }
    mut fn get_mut(k: read K, i: usize): (mut V from self)? {
        if i < self.n { present(unsafe { mut *self.vs.add(i) }) } else { none }
    }
    fn pair(k: read K): ((read V from self), usize) { (unsafe { read *self.vs }, 1usize) }
}
fn main() {
    var a = [10, 20]
    var t = Table(core.ptr.from_mut(a).cast<i32>(), 2usize, Option2(1u8))
    match t.get(1u8, 1usize) { present(v) => { if *v != 20 { return 1 } }, none => { return 2 } }
    match t.get(1u8, 2usize) { present(v) => { return 3 }, none => {} }
    match t.get_mut(1u8, 0usize) { present(v) => { if *v != 10 { return 4 } }, none => { return 5 } }
    match t.pair(1u8) { (v, n) => { if *v != 10 || n != 1usize { return 6 } } }
    0
}
