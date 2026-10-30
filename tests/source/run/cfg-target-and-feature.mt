// flags: --feature fast
@cfg(feature = "fast")
fn pick(): i32 { 1 }

@cfg(not(feature = "fast"))
fn pick(): i32 { 2 }

@cfg(all(target_pointer_width = "64", any(target_os = "macos", target_os = "linux")))
fn host(): i32 { 10 }

@cfg(not(all(target_pointer_width = "64", any(target_os = "macos", target_os = "linux"))))
fn host(): i32 { undefined_symbol }

@cfg(feature = "absent")
type Gone { x: UnknownType }

fn main(): i32 { if pick() == 1 && host() == 10 { 0 } else { 1 } }
