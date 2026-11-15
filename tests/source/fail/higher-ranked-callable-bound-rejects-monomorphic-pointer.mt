// expect-error: region 10:5 declared relationship
// expect-error: region 23:5 declared relationship
fn apply<F: for<region r> fn(read i32 from r): read i32 from r>(
    read operation: F, read value: i32): read i32 from value {
    operation(value)
}
fn invalid<region outer>(
    operation: fn(read i32 from outer): read i32 from outer,
    read value: i32 from outer): read i32 from value {
    apply(operation,value)
}
fn main(): i32 { 0 }

type Receiver<F> { operation: F }
extend<F: for<region r> fn(read i32 from r): read i32 from r> Receiver<F> {
    fn get(read value: i32): read i32 from value { (self.operation)(value) }
}
fn invalid_receiver<region outer>(
    operation: fn(read i32 from outer): read i32 from outer,
    read value: i32 from outer
): read i32 from value {
    let instance = Receiver(operation)
    instance.get(value)
}
