// arch: x86_64
// expect-error: feature 3:22 unsupported architecture operation
fn main() { unsafe { core::arch::x86_64::_mm_aesenc_si128() }; 0 }
