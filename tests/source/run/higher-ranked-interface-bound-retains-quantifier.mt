
interface Lifetime<region r> {}
type Universal {}
impl<region r> Universal implements Lifetime<region r> {}
fn accept<T: for<region r> Lifetime<region r>>(value: read T): i32 { 42 }
fn relay<T: for<region a> Lifetime<region a>>(value: read T): i32 { accept(value) }
fn main() {
    let value = Universal()
    if relay(value) == 42 { 0 } else { 1 }
}
