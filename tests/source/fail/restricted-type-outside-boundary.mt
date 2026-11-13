// expect-error: name 7:1 unresolved, inaccessible, ambiguous or cyclic import
module family {
    pub module inner {
        pub parent alias Number = i32
    }
}
import family.inner.Number
fn main(): i32 { 0 }
