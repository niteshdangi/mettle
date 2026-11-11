// expect-error: type 3:1 overlapping implementations cannot be selected by order
import core.clone.Clone
extend fn(take i32): i32 implements Clone {
    fn clone(): fn(take i32): i32 { self }
}
fn main(): i32 { 0 }
