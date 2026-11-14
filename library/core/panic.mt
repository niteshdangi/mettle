// Source-level panic: an unwind failure with a message, routed through the
// compiler-owned hook `core.intrinsics.panic_message`. Hosted code may recover
// it with `std.panic.catch_panic`; an uncaught panic exits with status 101.
// Freestanding execution has no unwind runtime and aborts (trap).
import super.text.Text

pub import core.marker.{RefUnwindSafe, UnwindSafe}

pub fn panic(read message: Text): Never {
    core.intrinsics.panic_message(message.as_bytes())
}

pub fn assert(condition: bool, read message: Text) {
    if !condition { panic(message) }
}

pub fn unreachable(): Never { panic("entered unreachable code") }
