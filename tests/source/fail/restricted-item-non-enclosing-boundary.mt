// expect-error: name 3:5 restricted visibility must name an enclosing module
module family {
    pub(package.other) fn value(): i32 { 42 }
}
fn main(): i32 { 0 }
