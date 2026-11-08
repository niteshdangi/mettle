// arch: x86_64
// expect-error: type 4:60 contract does not match interface
interface Ready { fn answer():i32; }
copy type Value implements Ready { @target_feature("avx2") fn answer():i32 { 42 } }
fn main() { 0 }
