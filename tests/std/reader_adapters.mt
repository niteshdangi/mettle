import alloc.string
import alloc.vec
import std.io

fn main(): i32 {
    let raw = "ab".as_bytes()
    var reader = io.slice_reader(raw)
    var text = string.new()
    let count = match capture reader.read_to_string(mut text) {
        success(n) => n,
        failure(_) => { return 1 }
    }
    if count != 2usize || text.as_text() != "ab" { return 2 }

    var prefixed = string.from_text("ok")
    let bad = [0xffu8]
    var bad_reader = io.slice_reader(bad)
    match capture bad_reader.read_to_string(mut prefixed) {
        success(_) => { return 3 },
        failure(_) => {}
    }
    if prefixed.as_text() != "ok" { return 4 }

    let stream = "xy".as_bytes()
    var source = io.slice_reader(stream)
    {
        var decoded = source.bytes()
        match decoded.next() {
            present(success(byte)) => { if byte != 120u8 { return 5 } },
            present(failure(_)) => { return 6 },
            none => { return 6 }
        }
        match decoded.next() {
            present(success(byte)) => { if byte != 121u8 { return 7 } },
            present(failure(_)) => { return 8 },
            none => { return 8 }
        }
        match decoded.next() {
            none => {},
            present(_) => { return 9 }
        }
    }

    let left = "ab".as_bytes()
    let right = "cd".as_bytes()
    var chained = io.slice_reader(left).chain(io.slice_reader(right))
    var collected = vec.new<u8>()
    let chained_count = match capture chained.read_to_end(mut collected) {
        success(n) => n,
        failure(_) => { return 10 }
    }
    if chained_count != 4usize || collected.as_slice()[0usize] != 97u8 || collected.as_slice()[3usize] != 100u8 {
        return 11
    }

    let limited_bytes = "abcdef".as_bytes()
    var limited = io.slice_reader(limited_bytes).`take`(2usize)
    var limited_out = vec.new<u8>()
    let limited_count = match capture limited.read_to_end(mut limited_out) {
        success(n) => n,
        failure(_) => { return 12 }
    }
    if limited_count != 2usize || limited_out.as_slice()[0usize] != 97u8 || limited_out.as_slice()[1usize] != 98u8 {
        return 13
    }

    let shared_bytes = "z".as_bytes()
    var shared = io.slice_reader(shared_bytes)
    {
        var borrowed = shared.by_ref()
        var one = [0u8; 1]
        let n = match capture borrowed.read_exact(one) {
            success(_) => 1usize,
            failure(_) => { return 14 }
        }
        if n != 1usize || one[0usize] != 122u8 { return 15 }
    }

    var sink = vec.new<u8>()
    {
        var borrowed = sink.by_ref()
        match capture borrowed.write_all("hi".as_bytes()) {
            success(_) => {},
            failure(_) => { return 16 }
        }
    }
    if sink.len() != 2usize || sink.as_slice()[0usize] != 104u8 || sink.as_slice()[1usize] != 105u8 {
        return 17
    }
    0
}
