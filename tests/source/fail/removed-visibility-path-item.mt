// expect-error: parse 3:8 'pub(path)' visibility was removed; use 'internal' for package visibility or 'pub parent' for the parent module
module family {
    pub(main.other) fn value(): i32 { 42 }
}
fn main(): i32 { 0 }
