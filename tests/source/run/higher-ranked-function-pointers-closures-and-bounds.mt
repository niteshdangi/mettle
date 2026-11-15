
fn apply<F: for<region r> fn(read i32 from r): read i32 from r>(
    read operation: F, read value: i32): read i32 from value {
    operation(value)
}
fn identity<region r>(read value: i32 from r): read i32 from r { read value }
type Callback<F: for<region r> fn(read i32 from r): read i32 from r> {
    operation: F
}
extend<F: for<region s> fn(read i32 from s): read i32 from s> Callback<F> {
    fn apply(read value: i32): read i32 from value {
        (self.operation)(value)
    }
}

type Frame<region r> { value: mut i32 from r }
interface Run { fn run(mut frame: Frame): Unit throws i32; }
type Action<F: for<region r> fn(mut Frame<region r>): Unit throws i32> {
    callback: F
}
extend<F: for<region r> fn(mut Frame<region r>): Unit throws i32> Action<F> implements Run {
    fn run(mut frame: Frame): Unit throws i32 { try (self.callback)(mut frame) }
}
fn increment<region r>(mut frame: Frame<region r>): Unit throws i32 {
    *frame.value += 1
}

fn main(): i32 {
    let pointer: for<region a> fn(read i32 from a): read i32 from a = identity
    let closure: for<region b> fn(read i32 from b): read i32 from b =
        fn(value) { read value }
    let value = 42
    let wrapped = Callback(pointer)
    var changed = 41
    {
        var frame = Frame(mut changed)
        let action = Action(increment)
        match capture action.run(mut frame) {
            success(_) => {},
            failure(_) => { return 1 }
        }
    }
    if changed != 42 { return 2 }
    if *apply(pointer,value) == 42 && *apply(closure,value) == 42 &&
       *wrapped.apply(value) == 42 { 0 } else { 1 }
}
