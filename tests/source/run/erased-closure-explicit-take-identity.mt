import alloc.boxed.Heap
interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}

fn wrap<region r>(read value: i32 from r): heap any Show from r {
    heap Held(read value)
}

fn explicit<region r>(take shown: Heap<any Show from r>): Heap<any Show from r> {
    let identity = take fn(take value: Heap<any Show from r>): Heap<any Show from r> {
        take value
    }
    identity(shown)
}

fn select_payload<region r, region s>(
    take first: Heap<any Show from r>, take second: Heap<any Show from s>
): Heap<any Show from r> {
    let choose = take fn(
        take value: Heap<any Show from r>, take unused: Heap<any Show from s>
    ): Heap<any Show from r> { take value }
    choose(first, second)
}

type StaticValue {}
extend StaticValue implements Show { fn value(): i32 { 42 } }
fn static_producer(): Heap<any Show from static> {
    let make = take fn(): Heap<any Show from static> { heap StaticValue() }
    make()
}

fn main(): i32 {
    let number = 42
    let shown = explicit(wrap(read number))
    if shown.value() != 42 { return 1 }
    var other = 7
    let selected = select_payload(wrap(read number), wrap(read other))
    other = 8
    if selected.value() != 42 { return 2 }
    if static_producer().value() != 42 { return 3 }
    0
}
