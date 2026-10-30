
enum Slot<K, V> { Empty, Full(K, V) }
fn value_of<K, V>(s: read Slot<K, V>): (read V from s)? {
    match s { Slot::Full(_, v) => present(read v), _ => none }
}
fn value_mut<K, V>(s: mut Slot<K, V>): (mut V from s)? {
    match mut s { Slot::Full(_, v) => present(mut v), _ => none }
}
type Cell { slot: Slot<i32, i32> }
impl Cell {
    fn get<region q>(k: read i32 from q): (read i32 from self)? { value_of(read self.slot) }
}
fn main(): i32 {
    var s = Slot::Full(1, 10)
    match take value_mut(mut s) { present(v) => { *v += 5 }, none => {} }
    let c = Cell(s)
    let k = 1
    match c.get(read k) { present(v) => *v - 15, none => 1 }
}
