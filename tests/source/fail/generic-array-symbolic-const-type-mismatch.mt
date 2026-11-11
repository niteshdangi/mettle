// expect-error: type 4:5 const argument does not match its declared type
fn accept<const N: usize>(read values: [i32; N]) {}
fn forward<const N: i32>(read values: [i32; N]) {
    accept(values)
}
fn main() {}
