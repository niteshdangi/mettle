// expect-error: name 8:5 private macro 'value' is not visible from this module
module family {
    pub module inner {
        pub(super) macro value { () => { 42 }; }
    }
}
fn main(): i32 {
    family.inner.value!()
}
