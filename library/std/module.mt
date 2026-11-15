// Root of the native hosted `std` library: depends on `core` and `alloc`.
// Operating-system access goes through libc and the `runtime/sys.cpp` shims.
pub module alloc
pub import core.{assert_matches, debug_assert_matches}
pub module sys
pub module io
pub module ffi
pub module path
pub module time
pub module fs
pub module env
pub module f32
pub module f64
pub module num
pub module process
pub module net
pub module panic
pub module sync
pub module collections
pub module task
pub module thread
pub module macros
pub module clone
pub module cmp
pub module convert
pub module ops
@cfg(any(target_os = "windows", target_os = "linux"))
pub module os
pub module formatting
