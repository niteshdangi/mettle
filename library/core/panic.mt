// Source-level panic: an unwind failure with a message, routed through the
// compiler-owned hook `core.intrinsics.panic_message`. Hosted code may recover
// it with `std.panic.catch_panic`; an uncaught panic exits with status 101.
// Freestanding execution has no unwind runtime and aborts (trap).
import super.cmp.PartialEq
import super.text.Text

pub fn panic(message: read Text): Never {
    core.intrinsics.panic_message(message.as_bytes())
}

pub fn assert(condition: bool, message: read Text) {
    if !condition { panic(message) }
}

pub fn assert_eq<T: PartialEq>(left: read T, right: read T, message: read Text) {
    if !left.eq(right) { panic(message) }
}

pub fn assert_ne<T: PartialEq>(left: read T, right: read T, message: read Text) {
    if left.eq(right) { panic(message) }
}

// Checked on every build. There is no separate debug-assertions switch.
pub fn debug_assert(condition: bool, message: read Text) { assert(condition, message) }
pub fn debug_assert_eq<T: PartialEq>(left: read T, right: read T, message: read Text) {
    assert_eq(left, right, message)
}
pub fn debug_assert_ne<T: PartialEq>(left: read T, right: read T, message: read Text) {
    assert_ne(left, right, message)
}

pub fn todo(message: read Text): Never { panic(message) }
pub fn unimplemented(message: read Text): Never { panic(message) }
pub fn unreachable(): Never { panic("entered unreachable code") }
