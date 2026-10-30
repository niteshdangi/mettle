
copy type Pair { first: i32; second: i32 }
interface Setter<region r> { mut fn set(value: read Pair from r): Unit; }
type Cell<region r> { value: read Pair from r }
extend<region r> Cell<region r> implements Setter<region r> {
    mut fn set(value: read Pair from r): Unit { self.value = read value }
}
fn set<region r>(cell: mut any Setter<region r>, value: read Pair from r) {
    cell.set(value)
}
fn main() {
    let original = Pair(0,0)
    let replacement = Pair(20,22)
    var cell = Cell(read original)
    set(cell,replacement)
    if cell.value.first + cell.value.second == 42 { 0 } else { 1 }
}
