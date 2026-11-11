import alloc.boxed.Box
interface Show { fn value(): i32; }
type Plain { value: i32 }
extend Plain implements Show { fn value(): i32 { self.value } }
type Fault { payload: Box<any Show>? }

interface Buffer {
    mut fn fill(): read i32 from self throws Fault;
    mut fn read_value(): i32 throws Fault {
        let view = try self.fill()
        *view
    }
}
type Source { value: i32; failed: bool }
extend Source implements Buffer {
    mut fn fill(): read i32 from self throws Fault {
        if self.failed {
            let payload: Box<any Show> = heap Plain(7)
            throw Fault(present(payload))
        }
        read self.value
    }
}

fn main(): i32 {
    var source = Source(42, false)
    match take capture source.read_value() {
        success(value) => { if value != 42 { return 1 } },
        failure(_) => { return 2 }
    }
    source.failed = true
    match take capture source.read_value() {
        success(_) => 3,
        failure(error) => match take error.payload {
            present(shown) => if shown.value() == 7 { 0 } else { 4 },
            none => 5
        }
    }
}
