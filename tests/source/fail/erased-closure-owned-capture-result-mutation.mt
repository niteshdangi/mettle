// expect-error: ownership 28:5 access or storage conflicts with a live read loan
import alloc.boxed.Box
interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}

fn wrap<region r>(read value: i32 from r): heap any Show from r {
    heap Held(read value)
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
    var number = 7
    let shown = capture_inferred(capture_explicit(wrap(read number)))
    number = 8
    shown.value()
}
