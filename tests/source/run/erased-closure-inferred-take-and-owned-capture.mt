import alloc.boxed.Box
interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}

fn wrap<region r>(read value: i32 from r): heap any Show from r {
    heap Held(read value)
}

fn inferred<region r>(take shown: Box<any Show from r>): Box<any Show from r> {
    let identity: fn(take Box<any Show from r>): Box<any Show from r> =
        take fn(value) { take value }
    identity(shown)
}

fn capture_explicit<region r>(take shown: Box<any Show from r>): Box<any Show from r> {
    let release = take fn(): Box<any Show from r> {
        take shown
    }
    release()
}

fn capture_inferred<region r>(take shown: Box<any Show from r>): Box<any Show from r> {
    let release = take fn() { take shown }
    release()
}

fn main(): i32 {
    let number = 42
    let passed = inferred(wrap(read number))
    if passed.value() != 42 { return 1 }
    let captured = capture_explicit(passed)
    if captured.value() != 42 { return 2 }
    let shown = capture_inferred(captured)
    if shown.value() == 42 { 0 } else { 3 }
}
