unsafe interface Produces {
    type Output;
    fn produce(): Self.Output;
}

pub copy type Producer<T: Copy> { value: T }

unsafe extend<T: Copy>
    Producer<T> implements Produces {
    type Output = T
    fn produce(): Self.Output { self.value }
}

fn main(): i32 {
    if Producer(42i32).produce() == 42i32 { 0 } else { 1 }
}
