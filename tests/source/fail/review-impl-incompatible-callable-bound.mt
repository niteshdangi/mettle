// expect-error: type 5:5 implementation method strengthens its interface bounds
interface Run { fn run<F: fn(): i32>(take f: F): i32; }
type Runner {}
extend Runner implements Run {
    fn run<F: fn(): bool>(take f: F): i32 { if f() { 1 } else { 0 } }
}
fn main(): i32 { 0 }
