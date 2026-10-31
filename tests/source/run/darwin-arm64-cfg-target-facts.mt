// arch: aarch64
@cfg(all(target_os = "macos", target_arch = "aarch64",
         target_family = "unix",
         target_endian = "little", target_pointer_width = "64",
         target_feature = "neon"))
fn selected_profile(): i32 { 42 }

@cfg(not(all(target_os = "macos", target_arch = "aarch64",
             target_family = "unix",
             target_endian = "little", target_pointer_width = "64",
             target_feature = "neon")))
fn selected_profile(): i32 { undefined_target_profile }

@cfg(target_feature = "aes")
fn optional_feature_enabled(): bool { false }

@cfg(not(target_feature = "aes"))
fn optional_feature_enabled(): bool { true }

@cfg(target_feature = "sha2")
fn sha2_is_baseline(): bool { false }

@cfg(not(target_feature = "sha2"))
fn sha2_is_baseline(): bool { true }

@cfg(target_feature = "crc")
fn crc_is_baseline(): bool { false }

@cfg(not(target_feature = "crc"))
fn crc_is_baseline(): bool { true }

@cfg(target_feature = "lse")
fn lse_is_baseline(): bool { false }

@cfg(not(target_feature = "lse"))
fn lse_is_baseline(): bool { true }

@cfg(target_feature = "fp16")
fn fp16_is_baseline(): bool { false }

@cfg(not(target_feature = "fp16"))
fn fp16_is_baseline(): bool { true }

@cfg(target_feature = "dotprod")
fn dotprod_is_baseline(): bool { false }

@cfg(not(target_feature = "dotprod"))
fn dotprod_is_baseline(): bool { true }

@cfg(target_feature = "rdm")
fn rdm_is_baseline(): bool { false }

@cfg(not(target_feature = "rdm"))
fn rdm_is_baseline(): bool { true }

fn main(): i32 {
    if selected_profile() == 42 && optional_feature_enabled() &&
       sha2_is_baseline() && crc_is_baseline() && lse_is_baseline() &&
       fp16_is_baseline() && dotprod_is_baseline() && rdm_is_baseline() {
        0
    } else { 1 }
}
