
interface Lifetime<region r> {}
type Universal {}
extend<region r> Universal implements Lifetime<region r> {}
fn accept<T: for<region r> Lifetime<region r>>(read value: T): i32 { 42 }
fn relay<T: for<region a> Lifetime<region a>>(read value: T): i32 { accept(value) }
fn main() {
    let value = Universal()
    if relay(value) == 42 { 0 } else { 1 }
}
