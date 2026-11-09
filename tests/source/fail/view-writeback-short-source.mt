// expect-error: ownership 5:95 live read loan
copy type R<region r> { value: read i32 from r }
fn set(mut target: R, read value: i32) { target.value = read value }
fn forward(mut target: R, read value: i32) { set(target,value) }
fn main() { let first = 1; var target = R(read first); { let short = 2; forward(target,short) }; *target.value }
