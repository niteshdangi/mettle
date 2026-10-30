
interface Add<Rhs> {
    type Output;
    fn add(rhs: read Rhs): Self.Output;
}
type Number { value: i32 }
extend Number implements Add<Number> {
    type Output = Number
    fn add(rhs: read Number): Number { Number(self.value + rhs.value) }
}
fn sum<T: Add<T, Output=T>>(left: T, right: T): T {
    let outer = fn(): T {
        let inner = fn(): T { left.add(right) }
        inner()
    }
    outer()
}
fn main(): i32 {
    let result = sum(Number(20),Number(22))
    if result.value == 42 { 0 } else { 1 }
}
