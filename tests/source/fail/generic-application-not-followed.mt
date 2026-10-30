// expect-error: parse 4:14 comparisons do not chain
fn main() {
    let a = 1; let b = 2; let c = 3
    if a < b > c { 0 } else { 1 }
}
