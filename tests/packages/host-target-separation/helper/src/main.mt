@cfg(feature = "host")
pub fn host_value(): i32 { 99 }
@cfg(not(feature = "host"))
pub fn host_value(): i32 { 0 }

@cfg(feature = "target")
pub fn target_value(): i32 { 1 }
@cfg(not(feature = "target"))
pub fn target_value(): i32 { 0 }
