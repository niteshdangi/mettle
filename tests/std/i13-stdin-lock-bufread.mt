// stdin: alpha\nbeta\r\ngamma\ndelta
// expect-stdout: ok\n
// Stdin handles share one buffer: a StdinLock reads ahead and a later handle
// sees the remaining bytes; BufRead exposes fill_buf, consume and lines.
import std.io.{BufRead, Error, Reader, Writer}
import alloc.string
import alloc.vec

fn run(): i32 throws Error {
    {
        var lock = std.io.stdin().lock()
        let avail = try lock.fill_buf()
        if avail.len() < 6usize || avail[0] != 97u8 { return 1 }
        lock.consume(2usize)
        var rest = vec.new<u8>()
        let n = try lock.read_until(10u8, rest)
        if n != 4usize || rest.len() != 4usize || rest[0] != 112u8 { return 2 }
        var one = [0u8; 4]
        let got = try lock.read_some(one)
        if got != 4usize || one[0] != 98u8 { return 3 }
    }
    // The lock was dropped; the unlocked handle continues from the shared buffer.
    var line = string.new()
    let count = try std.io.stdin().read_line(line)
    if count != 3usize || line.len() != 3usize { return 4 }
    var seen = 0
    var held = std.io.stdin().lock()
    for item in held.lines() {
        let text = match take item { success(t) => t, failure(e) => { throw e } }
        seen += 1
        if seen == 1 && text.len() != 5usize { return 5 }
        if seen == 2 && text.len() != 5usize { return 6 }
    }
    if seen != 2 { return 7 }
    var out = std.io.stdout()
    try out.write_all("ok\n".as_bytes())
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => 100 }
}
