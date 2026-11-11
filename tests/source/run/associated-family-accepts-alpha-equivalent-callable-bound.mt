interface Family {
    type Item<F: for<region r> fn(read i32 from r): read i32 from r>;
}
fn accept<T: Family,
    F: for<region s> fn(read i32 from s): read i32 from s>(
    take value: T.(Family).Item<F>
): Unit { let _ = value }
interface Inferred { type Result; }
extend<T, F: for<region r> fn(read i32 from r): read T from r> F implements Inferred {
    type Result = T
}
fn inferred<G: for<region s> fn(read i32 from s): read i32 from s>(
    read operation: G
): Unit { let _: G.(Inferred).Result = 42 }
fn main(): i32 { 0 }
