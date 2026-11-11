extern "C" { unsafe fn missing_doctest_symbol(): Unit; }

/// ```compile_fail
/// unsafe { missing_doctest_symbol(); }
/// ```
pub fn documented() {}
