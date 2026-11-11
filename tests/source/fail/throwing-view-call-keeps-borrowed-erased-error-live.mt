// expect-error: ownership 26:5 access or storage lifetime conflicts
import alloc.boxed.Box
interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}
type Fault<region r> { payload: Box<any Show from r> }

interface Buffer {
    fn fill<region r>(receiver mut self: Self from r): i32 throws Fault<region r>;
}
type Source { value: i32 }
extend Source implements Buffer {
    fn fill<region r>(receiver mut self: Self from r): i32 throws Fault<region r> {
        throw Fault(heap Held(read self.value))
    }
}

fn main(): i32 {
    var source = Source(7)
    let error = match take capture source.fill() {
        success(_) => { return 1 },
        failure(error) => error
    }
    source.value = 8
    error.payload.value()
}
