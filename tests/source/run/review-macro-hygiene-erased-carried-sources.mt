import alloc.boxed.Heap

interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}

fn wrap<region r>(read value: i32 from r): heap any Show from r {
    heap Held(read value)
}

macro selector {
    ($r:ident) => {
        for<region r> fn(
            take Heap<any Show from $r>, take Heap<any Show from r>
        ): Heap<any Show from $r>
    };
}

fn select_payload<region r, region s>(
    take first: Heap<any Show from r>, take second: Heap<any Show from s>
): Heap<any Show from r> {
    let choose: selector!(r) = take fn(value, unused) { take value }
    choose(first, second)
}

fn main(): i32 {
    let number = 42
    var other = 7
    let selected = select_payload(wrap(read number), wrap(read other))
    other = 8
    selected.value() - 42
}
