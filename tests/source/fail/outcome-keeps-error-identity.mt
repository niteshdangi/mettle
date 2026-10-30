// expect-error: effects 5:33 propagated error
copy enum First { Bad }
copy enum Second { Bad }
fn fail(): i32 throws First { throw First::Bad }
fn wrong(): i32 throws Second { try fail() }
fn main() { 0 }
