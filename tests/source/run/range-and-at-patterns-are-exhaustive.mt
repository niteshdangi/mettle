
fn classify(value: i32) {
    match value {
        -2147483648..0 => 0,
        answer @ 0..=42 => answer,
        43..=2147483647 => 0
    }
}
fn main() { if classify(42) == 42 && classify(-1) == 0 && classify(43) == 0 { 0 } else { 1 } }
