// expect-error: type 3:5 invalid primitive operation or operand types
fn expose<T: Copy, const N: usize>(mut value: pinned mut [T; N]): mut [T; N] from value {
    value.get_mut()
}
fn main() { 0 }
