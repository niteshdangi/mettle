interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}

fn total<region r>(shown: heap any Show from r): i32 { shown.value() }

fn generic_owner<region r, T: Show>(take value: T from r): heap any Show from r {
    heap value
}

interface Build<T>: Sized { static fn build(take value: T): Self; }
type Kept<region r> { shown: heap any Show from r; }
extend<region r, T: Show> Kept<region r> implements Build<T from r> {
    static fn build(take value: T from r): Kept<region r> {
        Kept(heap value)
    }
}

// The result owns no borrow; each erased owner is bounded by its own site.
fn both<region r>(read value: i32 from r): i32 {
    let kept: heap any Show from r = heap Held(read value)
    let built = Kept<region r>.(Build<Held<region r> from r>).build(Held(read value))
    kept.value() + total(heap Held(read value)) +
        generic_owner(Held(read value)).value() + built.shown.value()
}

fn main(): i32 {
    let value = 40
    if both(read value) == 160 { 0 } else { 1 }
}
