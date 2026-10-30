// arch: aarch64
// expect-error: feature 3:16 unsupported core feature detection
fn main() { if is_aarch64_feature_detected!("aes") { 0 } else { 1 } }
