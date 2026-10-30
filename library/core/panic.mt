// Source-level panic: a nonrecoverable failure with a message, routed through
// the single compiler-owned hook `core::intrinsics::panic_message`. A hosted
// runtime reports the message on stderr, unwinds with cleanup and exits with
// status 101; a freestanding build has no sink and aborts (trap).
import super::text::Text;

pub fn panic(message: read Text): Never {
    core::intrinsics::panic_message(message.as_bytes())
}

pub fn assert(condition: bool, message: read Text) {
    if !condition { panic(message) }
}

pub fn unreachable(): Never { panic("entered unreachable code") }
