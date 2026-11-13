// expect-error: name 7:1 unresolved, inaccessible, ambiguous or cyclic import
module family {
    pub module inner {
        pub parent static VALUE: i32 = 42
    }
}
import family.inner.VALUE
fn main(): i32 { 0 }
