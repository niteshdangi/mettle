// arch: aarch64
// expect-error: feature 3:37 implicit destructor dispatch
type Value { @target_feature("aes") drop {} }
fn main() { let value=Value(); 0 }
