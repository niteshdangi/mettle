interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}

fn erase<region r>(value: read i32 from r): heap any Show from r {
    heap Held(read value)
}

fn main(): i32 {
    let value = 42
    let shown = erase(read value)
    if shown.value() == 42 { 0 } else { 1 }
}
