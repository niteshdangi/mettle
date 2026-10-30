
fn negate(n: i32) { if n == 0 { true } else { !invert(n - 1) } }
fn invert(n: i32) { negate(n) }
fn bit(n: i32) { if n == 0 { true } else { both(n - 1) } }
fn both(n: i32) { bit(n) & bit(n) }
fn main() { if negate(2) && bit(3) { 0 } else { 1 } }
