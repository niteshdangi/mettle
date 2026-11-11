// expect-error: type 6:12 inferred array length is outside the const parameter type range

fn accept<const N: u8>(read values: [i32; N]) {}
fn main() {
    let values = [0; 256]
    accept(values)
}
