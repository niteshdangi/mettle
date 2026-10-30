// expect-error-count: 1
// expect-error: region 5:11 unknown region

fn first<region r>(value: read i32 from r): i32 { 0 }
fn second(value: read i32 from r): i32 { 0 }
fn main() { 0 }
