// expect-error: name 7:1 unresolved, inaccessible, ambiguous or cyclic import
module family {
    pub module inner {
        pub parent fn answer(): i32 { 42 }
    }
}
import family.inner.answer
fn main(): i32 { answer() }
