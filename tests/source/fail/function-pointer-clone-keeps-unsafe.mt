// expect-error: unsafe 7:5 requires an unsafe block
import core.clone.Clone
fn answer(): i32 { 42 }
fn main(): i32 {
    let original: unsafe fn(): i32 = answer
    let cloned = original.clone()
    cloned()
}
