// expect-error-count: 1
// expect-error: ownership 4:41 caller-owned storage
copy type R<region r> { value: read i32 from r }
fn bad(mut target: R) { let owned = 42; target.value = read owned }
fn main() { 0 }
