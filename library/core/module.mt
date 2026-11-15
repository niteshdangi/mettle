// Root of the native `core` library: no allocator implementation or operating
// system.
// `ptr` augments the compiler's pointer operations with the NonNull type and
// `sync` adds interface implementations to the compiler's atomic types; other compiler built-in modules remain compiler-owned.
pub macro assert_matches {
    ($value:expr, $pattern:pat if $guard:expr, $message:expr $(,)?) => {
        match $value {
            $pattern if $guard => {},
            _ => core.panic.panic_fmt($message)
        }
    };
    ($value:expr, $pattern:pat, $message:expr $(,)?) => {
        match $value {
            $pattern => {},
            _ => core.panic.panic_fmt($message)
        }
    };
    ($value:expr, $pattern:pat if $guard:expr, $message:expr, $($arguments:expr),+ $(,)?) => {
        match $value {
            $pattern if $guard => {},
            _ => core.panic.panic_fmt($message, $($arguments),+)
        }
    };
    ($value:expr, $pattern:pat, $message:expr, $($arguments:expr),+ $(,)?) => {
        match $value {
            $pattern => {},
            _ => core.panic.panic_fmt($message, $($arguments),+)
        }
    };
    ($value:expr, $pattern:pat if $guard:expr $(,)?) => {
        match $value {
            $pattern if $guard => {},
            _ => core.panic.panic("assertion failed: pattern did not match")
        }
    };
    ($value:expr, $pattern:pat $(,)?) => {
        match $value {
            $pattern => {},
            _ => core.panic.panic("assertion failed: pattern did not match")
        }
    };
}

@cfg(debug_assertions)
pub macro debug_assert_matches {
    ($value:expr, $pattern:pat if $guard:expr, $message:expr $(,)?) => {
        core.assert_matches!($value, $pattern if $guard, $message)
    };
    ($value:expr, $pattern:pat, $message:expr $(,)?) => {
        core.assert_matches!($value, $pattern, $message)
    };
    ($value:expr, $pattern:pat if $guard:expr, $message:expr, $($arguments:expr),+ $(,)?) => {
        core.assert_matches!($value, $pattern if $guard, $message, $($arguments),+)
    };
    ($value:expr, $pattern:pat, $message:expr, $($arguments:expr),+ $(,)?) => {
        core.assert_matches!($value, $pattern, $message, $($arguments),+)
    };
    ($value:expr, $pattern:pat if $guard:expr $(,)?) => {
        core.assert_matches!($value, $pattern if $guard)
    };
    ($value:expr, $pattern:pat $(,)?) => {
        core.assert_matches!($value, $pattern)
    };
}

@cfg(not(debug_assertions))
pub macro debug_assert_matches {
    ($value:expr, $pattern:pat if $guard:expr, $message:expr $(,)?) => {};
    ($value:expr, $pattern:pat, $message:expr $(,)?) => {};
    ($value:expr, $pattern:pat if $guard:expr, $message:expr, $($arguments:expr),+ $(,)?) => {};
    ($value:expr, $pattern:pat, $message:expr, $($arguments:expr),+ $(,)?) => {};
    ($value:expr, $pattern:pat if $guard:expr $(,)?) => {};
    ($value:expr, $pattern:pat $(,)?) => {};
}

pub module any
pub module alloc
pub module array
pub module ascii
pub module borrow
pub module cell
pub module char
pub module clone
pub module cmp
pub module convert
pub module default
pub module error
pub module ffi
pub module f32
pub module f64
pub module float
pub module fmt
pub module future
pub module hash
pub module iter
pub module marker
pub module mem
pub module net
pub module num
pub module ops
pub module option
pub module outcome
pub module panic
pub module pin
pub module ptr
pub module range
pub module slice
pub module sync
pub module text
module unicode_data
