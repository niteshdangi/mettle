// expect-error: ownership 18:5 live read loan

copy type Pair { first: i32; second: i32 }
interface Setter<region r> { mut fn set(read value: Pair from r): Unit; }
type Cell<region r> { value: read Pair from r }
extend<region r> Cell<region r> implements Setter<region r> {
    mut fn set(read value: Pair from r): Unit { self.value = read value }
}
fn set<region r>(mut cell: any Setter<region r>, read value: Pair from r) {
    cell.set(value)
}
fn main() {
    let original = Pair(0,0)
    var cell = Cell(read original)
    {
        let replacement = Pair(20,22)
        set(cell,replacement)
    }
    cell.value.first + cell.value.second
}
