// expect-exit: 0
// profiles: debug release
// Behavioral evidence for the blanket rows used by the blanket-std lane:
// Borrow (T borrows T), From<T> for T, Into<A> for A, ToOwned through Clone,
// and ToString through Display. Each result is checked; any mismatch returns a
// distinct nonzero code.

import alloc.arc
import core.borrow.{ Borrow, ToOwned }
import core.clone.Clone
import core.convert.{ From, Into }
import core.fmt.Message
import core.fmt.buffer_writer
import alloc.string.ToString
import std.net

fn emit(message: format Message, buffer: mut [u8]): usize {
    var out = buffer_writer(mut buffer)
    let ignored = capture message.write_to(mut out)
    out.len()
}

fn same(buffer: read [u8], length: usize, expected: read Text): bool {
    let want = expected.as_bytes()
    if length != want.len() { return false }
    var i = 0usize
    while i < length {
        if buffer[i] != want[i] { return false }
        i += 1usize
    }
    true
}

// True when `text` holds exactly the characters the format message renders.
fn text_is_render(text: read Text, message: format Message): bool {
    var buffer = [0u8; 64]
    let n = emit(message, mut buffer)
    same(read buffer, n, text)
}

fn main(): i32 {
    // alloc.arc.Arc<i32>: Borrow, From<T>, Into<A>, ToOwned (via Clone), ToString
    let arc_value = arc.new(41)
    let arc_view = arc.Arc<i32>.(Borrow<arc.Arc<i32>>).borrow(arc_value)
    if *arc_view.get() != 41 { return 1 }

    let wrapped = arc.Arc<i32>.(From<arc.Arc<i32>>).`from`(arc_value)
    if *wrapped.get() != 41 { return 2 }

    let carried = arc.Arc<i32>.(Into<arc.Arc<i32>>).into(arc.new(42))
    if *carried.get() != 42 { return 3 }

    let kept = arc.new(43)
    let owned_value = kept.to_owned()
    let cloned_value = kept.clone()
    if *owned_value.get() != *cloned_value.get() { return 4 }
    if *owned_value.get() != 43 { return 5 }

    let text_value = kept.to_string()
    if !text_is_render(text_value.as_text(), f"{kept}") { return 6 }

    // std.net.Ipv4Addr: Borrow, From<T>, Into<A>, ToString
    let ip_value = std.net.localhost()
    let ip_view = std.net.Ipv4Addr.(Borrow<std.net.Ipv4Addr>).borrow(ip_value)
    let ip_copy: std.net.Ipv4Addr = *ip_view
    if ip_copy != std.net.localhost() { return 7 }

    let via_from = std.net.Ipv4Addr.(From<std.net.Ipv4Addr>).`from`(std.net.localhost())
    if via_from != std.net.localhost() { return 8 }

    let via_into = std.net.Ipv4Addr.(Into<std.net.Ipv4Addr>).into(std.net.localhost())
    if via_into != std.net.localhost() { return 9 }

    let ip_text = std.net.localhost().to_string()
    if !text_is_render(ip_text.as_text(), f"{ip_value}") { return 10 }
    if !same(read ip_text.as_bytes(), ip_text.as_bytes().len(), "127.0.0.1") { return 11 }

    0
}
