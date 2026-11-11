interface Lifetime<region r> {}
interface Family<region r> { type Item: Lifetime<region r>; }
fn require<region r, T: Lifetime<region r>>(read value: T): i32 { 42 }
fn relay<region r, T: Family<region r>>(read value: T.(Family<region r>).Item): i32 {
    require<region r>(value)
}
fn main(): i32 { 0 }
