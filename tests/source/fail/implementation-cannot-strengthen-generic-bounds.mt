// expect-error-count: 1
// expect-error: type 7:5 strengthens

interface Accept { fn accept<T>(value: T): Unit; }
type Number {}
extend Number implements Accept {
    fn accept<T: Copy>(value: T): Unit { let first = value; let second = value }
}
fn main() { 0 }
