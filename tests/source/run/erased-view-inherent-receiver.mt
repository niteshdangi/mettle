interface Value { fn value(): i32; }
type Number { value: i32 }
extend Number implements Value {
    fn value(): i32 { self.value }
}

extend<region r> read any Value from r {
    fn read_value<T: Copy>(value: T): T { value }
}
extend<region r> mut any Value from r {
    mut fn mut_value(): i32 { self.value() }
}

fn read_value<region r>(read value: any Value from r): i32 {
    value.read_value<i32>(value.value())
}
fn mut_value<region r>(mut value: any Value from r): i32 {
    value.mut_value()
}

fn main(): i32 {
    var value = Number(21)
    read_value(read value) + mut_value(mut value) - 42
}
