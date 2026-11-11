const fn comparisons(): bool {
    'a' < 'b' && 'a' <= 'a' && 'b' > 'a' && 'b' >= 'b' &&
    'a' == 'a' && 'a' != 'b'
}
const CORRECT: bool = comparisons()
fn main(): i32 { if CORRECT { 0 } else { 1 } }
