// expect-error: type 5:26 does not satisfy Sized

fn require_sized<T>(read value: T): Unit { () }
interface Bound<Rhs = Self> {
    fn invalid(): Unit { require_sized(self) }
}
fn main(): i32 { 0 }
