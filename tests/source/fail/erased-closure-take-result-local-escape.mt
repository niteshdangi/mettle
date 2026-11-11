// expect-error: ownership 30:5 access or storage lifetime conflicts with a live read loan
import alloc.boxed.Box
interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}

fn wrap<region r>(read value: i32 from r): heap any Show from r {
    heap Held(read value)
}

fn explicit<region r>(take shown: Box<any Show from r>): Box<any Show from r> {
    let identity = take fn(take value: Box<any Show from r>): Box<any Show from r> {
        take value
    }
    identity(shown)
}

fn inferred<region r>(take shown: Box<any Show from r>): Box<any Show from r> {
    let identity: fn(take Box<any Show from r>): Box<any Show from r> =
        take fn(value) { take value }
    identity(shown)
}

fn main(): i32 {
    let shown = {
        let number = 7
        inferred(explicit(wrap(read number)))
    }
    shown.value()
}
