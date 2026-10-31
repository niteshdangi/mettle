// expect-error: type 11:5 unsatisfied interface bound

interface Carrier { type Item<region r>; }
type Borrowed<region r> { value: read i32 from r }
extend<region r> Borrowed<region r> implements Carrier {
    type Item<region r> = read i32 from r
}

fn transfer<T: Transferable>(value: take T): Unit {}
fn carry<T: Carrier, region r>(value: take T.(Carrier).Item<region r>) {
    transfer(value)
}

fn main(): i32 { 0 }
