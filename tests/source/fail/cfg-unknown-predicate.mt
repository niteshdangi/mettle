// expect-error: attribute 2:6 unknown cfg predicate
@cfg(bogus = "x")
fn f() {}
fn main(): i32 { 0 }
