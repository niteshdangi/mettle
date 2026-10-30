// expect-error: effects 3:12 explicit throws
copy enum Error { Bad }
fn bad() { throw Error::Bad }
fn main() { 0 }
