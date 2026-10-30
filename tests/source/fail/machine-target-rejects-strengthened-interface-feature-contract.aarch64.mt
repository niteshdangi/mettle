// arch: aarch64
// expect-error: type 4:59 contract does not match interface
interface Ready { fn answer():i32; }
copy type Value implements Ready { @target_feature("aes") fn answer():i32 { 42 } }
fn main() { 0 }
