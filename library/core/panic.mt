// Source-level panic: an unwind failure with a message, routed through the
// compiler-owned hook `core.intrinsics.panic_message`. Hosted code may recover
// it with `std.panic.catch_panic`; an uncaught panic exits with status 101.
// Freestanding execution has no unwind runtime and aborts (trap).
import super.text.Text
import super.fmt.{Message, Write, Error}

pub import core.marker.{RefUnwindSafe, UnwindSafe}

type PanicSink {
    context: ptr<mut u8>
    write: unsafe extern "C" fn(ptr<mut u8>, ptr<read u8>, u64): Unit
}

extend PanicSink implements Write {
    mut fn write_str(read text: Text): Unit throws Error {
        let bytes = text.as_bytes()
        unsafe {
            (self.write)(self.context, core.slice.data(bytes),
                         bytes.len() as u64)
        }
    }
}

unsafe extern "C" fn render_panic<region r>(
    context: ptr<mut u8>,
    write: unsafe extern "C" fn(ptr<mut u8>, ptr<read u8>, u64): Unit,
    sink_context: ptr<mut u8>
): Unit {
    let message = unsafe { read *context.cast<Message<region r>>() }
    var sink = PanicSink(sink_context, write)
    match capture message.write_to(mut sink) {
        success(_) => {},
        failure(_) => core.intrinsics.abort()
    }
}

pub fn panic_fmt<region r>(message: format Message<region r>): Never {
    unsafe {
        core.intrinsics.panic_fmt(message, render_panic<region r>)
    }
}

pub fn panic(read message: Text): Never {
    core.intrinsics.panic_message(message.as_bytes())
}

pub fn assert(condition: bool, read message: Text) {
    if !condition { panic(message) }
}

pub fn unreachable(): Never { panic("entered unreachable code") }
