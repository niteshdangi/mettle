import alloc.boxed.Heap
interface Show { fn value(): i32; }
type Plain { value: i32 }
extend Plain implements Show { fn value(): i32 { self.value } }
type Fault { payload: Heap<any Show>? }

fn check_failure(failed: bool): Unit throws Fault {
    if failed {
        let payload: Heap<any Show> = heap Plain(7)
        throw Fault(present(payload))
    }
}
interface Buffer {
    mut fn fill(): read i32 from self throws Fault;
    mut fn read_value(): i32 throws Fault {
        let view = try self.fill()
        *view
    }
}
type Source<region r> { value: read i32 from r; failed: bool }
extend<region r> Source<region r> implements Buffer {
    mut fn fill(): read i32 from self throws Fault {
        try check_failure(self.failed)
        self.value
    }
}
type Wrapped<B: Buffer> { inner: B }
extend<B: Buffer> Wrapped<B> implements Buffer {
    mut fn fill(): read i32 from self throws Fault {
        try self.inner.fill()
    }
}

fn main(): i32 {
    let backing = 42
    var source = Wrapped(Source(read backing, false))
    match take capture source.read_value() {
        success(value) => { if value != 42 { return 1 } },
        failure(_) => { return 2 }
    }
    source.inner.failed = true
    match take capture source.read_value() {
        success(_) => 3,
        failure(error) => match take error.payload {
            present(shown) => if shown.value() == 7 { 0 } else { 4 },
            none => 5
        }
    }
}
