// arch: x86_64
// expect-error: feature 3:37 implicit destructor dispatch
type Value { @target_feature("avx2") drop {} }
fn main() { let value=Value(); 0 }
