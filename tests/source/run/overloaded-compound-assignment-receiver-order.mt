
module core {
    pub module ops {
        pub interface AddAssign<Rhs> {
            mut fn add_assign(rhs: read Rhs): Unit;
        }
    }
}
type Number { value: i32 }
extend Number implements core.ops.AddAssign<Number> {
    mut fn add_assign(rhs: read Number): Unit { self.value += rhs.value }
}
fn select(values: mut [Number;1], trace: mut i32): mut Number from values {
    trace = trace * 10 + 1
    mut values[0]
}
fn argument(trace: mut i32): Number {
    trace = trace * 10 + 2
    Number(2)
}
fn main() {
    var trace = 0
    var values = [Number(1)]
    *select(values,trace) += argument(trace)
    if trace == 12 && values[0].value == 3 { 0 } else { 1 }
}
