// expect-error: name 7:18 private macro 'value' is not visible from this module
module a {
    pub module b {
        pub parent macro value { () => { 42 }; }
    }
}
fn main(): i32 { a.b.value!() }
