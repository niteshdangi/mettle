interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}

fn total<region r>(shown: heap any Show from r): i32 { shown.value() }

// The result owns no borrow; each erased owner is bounded by its own site.
fn both<region r>(read value: i32 from r): i32 {
    let kept: heap any Show from r = heap Held(read value)
    kept.value() + total(heap Held(read value))
}

fn main(): i32 {
    let value = 40
    if both(read value) == 80 { 0 } else { 1 }
}
