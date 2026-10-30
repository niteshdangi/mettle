// expect-error: unsafe 2:62 operation requires an unsafe block or unsafe function
fn main() { var value = 0; let p = core.ptr.from_mut(value); core.ptr.`copy`(p,p,1); 0 }
