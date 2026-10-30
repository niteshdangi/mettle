// arch: aarch64
// expect-error: feature 3:22 unsupported architecture operation
fn main() { unsafe { core.arch.aarch64.vaeseq_u8() }; 0 }
