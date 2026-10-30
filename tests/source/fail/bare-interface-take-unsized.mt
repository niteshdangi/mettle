// expect-error: type 7:13 unsatisfied interface obligation
// By-value use keeps the Sized requirement, so an unsized implementor is rejected.
interface Weigh { fn weight(): usize; }
extend Text implements Weigh { fn weight(): usize { self.len() } }
fn by_take(item: take Weigh): usize { item.weight() }
fn main(): i32 {
    let n = by_take("abc")
    0
}
