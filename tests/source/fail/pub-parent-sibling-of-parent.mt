// expect-error: name 8:25 unresolved or inaccessible function
module a {
    pub module b {
        pub parent fn answer(): i32 { 42 }
    }
}
module d {
    pub fn get(): i32 { super.a.b.answer() }
}
fn main(): i32 { d.get() }
