// expect-error: effects 4:13 requires try or capture
copy enum Error { Bad }
fn fail(): i32 throws Error { throw Error.Bad }
fn main() { fail() }
