// expect-error-count: 1
// expect-error: region 5:16 unknown region

fn first<region r>(read value: i32 from r): i32 { 0 }
fn second(read value: i32 from r): i32 { 0 }
fn main() { 0 }
