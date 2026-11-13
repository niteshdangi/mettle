module helper { pub fn value(): i32 { 42 } }
module outer {
    module inner {
        import main.helper.value
        pub fn get(): i32 { value() }
    }
    pub fn get(): i32 { inner.get() }
}
fn main(): i32 { outer.get() - 42 }
