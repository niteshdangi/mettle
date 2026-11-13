import core.fmt
import core.fmt.Debug
import core.text.Text
import std.time.{duration, system_time_from_parts, now}

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn debug_renders<T: Debug>(read value: T): bool {
    var buffer = [0u8; 128]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => writer.len() > 24usize,
        failure(error) => false
    }
}

fn main(): i32 {
    let span = duration(3u64, 7u32)
    let span_copy = span
    if !span.same(span_copy) { return 1 }
    if !debug_is(span, "Duration { secs: 3, nanos: 7 }") { return 2 }
    let stamp = system_time_from_parts(-2i64, 5u32)
    let stamp_copy = stamp
    if stamp != stamp_copy { return 3 }
    if !debug_is(stamp, "SystemTime { secs: -2, nanos: 5 }") { return 4 }
    let instant = now()
    let instant_copy = instant
    if instant != instant_copy || !debug_renders(instant) { return 5 }
    if !debug_is(duration(0u64, 0u32), "Duration { secs: 0, nanos: 0 }") { return 6 }
    0
}
