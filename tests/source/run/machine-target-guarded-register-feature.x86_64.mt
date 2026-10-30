// arch: x86_64

fn main() {
    if is_x86_feature_detected!("avx") {
        unsafe { asm!("vxorpd {value:y}, {value:y}, {value:y}",
                      value = out(ymm_reg) _, options(nomem,nostack)) }
    }
    0
}
