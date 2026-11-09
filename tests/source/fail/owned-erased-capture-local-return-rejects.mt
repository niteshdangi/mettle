// expect-error: region 13:26 erased owner payload borrow does not outlive
import alloc.boxed.Box
interface Show { fn value(): i32; }
type Held<region r> { value: read i32 from r; drop {} }
extend<region r> Held<region r> implements Show {
    fn value(): i32 { *self.value }
}

fn wrap<region r>(read value: i32 from r): Box<any Show from r> {
    heap Held(read value)
}

fn leak(): Box<any Show> {
    let value = 42
    let owner = wrap(read value)
    owner
}

fn main(): i32 {
    leak()
    0
}
