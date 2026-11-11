import core.future.{Future, Poll, Context, noop_waker}
import core.fmt
import core.fmt.Debug

pub macro drive {
    ($future:expr) => {{
        let waker = noop_waker()
        var slot = core.pin.pin($future)
        loop {
            var cx = Context.from_waker(read waker)
            match take slot.as_mut().poll(mut cx) {
                Poll.Ready(value) => { return value },
                Poll.Pending => {}
            }
        }
    }};
}

pub macro drive_counted {
    ($future:expr) => {{
        let waker = noop_waker()
        var slot = core.pin.pin($future)
        var spins = 0
        loop {
            var cx = Context.from_waker(read waker)
            match take slot.as_mut().poll(mut cx) {
                Poll.Ready(value) => { return (value, spins) },
                Poll.Pending => { spins = spins + 1 }
            }
        }
    }};
}

pub macro debug_is {
    ($t:ty, $value:expr, $expected:expr) => {{
        var storage = [0u8; 200]
        var writer = fmt.buffer_writer(mut storage)
        var formatter = fmt.formatter(mut writer, fmt.spec())
        match capture $t.(Debug).fmt($value, mut formatter) {
            success(unit) => {},
            failure(error) => { return false }
        }
        let written = writer.len()
        match fmt.written_text(read storage, written) {
            present(actual) => actual == $expected,
            none => false
        }
    }};
}
