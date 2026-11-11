interface Marker {}
extend i32 implements Marker {}
fn check<
    A: Marker, B: Marker, C: Marker, D: Marker,
    E: Marker, F: Marker, G: Marker, H: Marker,
    I: Marker, J: Marker, K: Marker, L: Marker
>(value: i32): i32 { value }
fn main(): i32 {
    check<
        i32, i32, i32, i32, i32, i32,
        i32, i32, i32, i32, i32, i32
    >(42) - 42
}
