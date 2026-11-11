import alloc.boxed.Box
interface Show { fn value(): i32; }
type Plain { value: i32 }
extend Plain implements Show { fn value(): i32 { self.value } }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}

fn make(): heap any Show { heap Plain(42) }
fn identity<T>(take value: T): T { value }
fn wrap<region r>(read value: i32 from r): heap any Show from r {
    heap Held(read value)
}
fn pass<region r>(take shown: Box<any Show from r>): Box<any Show from r> {
    identity(shown)
}

fn main(): i32 {
    let number = 42
    let shown = pass(wrap(read number))
    let static_owner = identity(make())
    if shown.value() == 42 && static_owner.value() == 42 { 0 } else { 1 }
}
