// A parent serves on loopback while a child process (this program) connects.
import std.io.{Error, Reader, Writer}
import std.process.Stdio
import std.ffi
import alloc.vec.List
import std.time.from_millis

fn serve(): i32 throws Error {
    var listener = try std.net.tcp_listen(std.net.socket_addr(std.net.localhost(), 0u16))
    let port = (try listener.local_addr()).port
    var me = std.process.command(std.env.args()[0usize].as_os_str())
    me.arg_text("client")
    let digits = ffi.os_string_from_vec(decimal(port as u32))
    me.arg(digits.as_os_str())
    me.stdout(Stdio.Piped)
    var child = try me.spawn()
    try listener.set_accept_timeout(present(from_millis(20000u64)))
    let pair = try listener.accept()
    var conn = pair.0
    try conn.set_read_timeout(present(from_millis(20000u64)))
    var buf = [0u8; 32]
    let n = try conn.read_some(buf)
    if n != 4usize || buf[0usize] != 112u8 { return 1 }
    try conn.write_all("PONG".as_bytes())
    let out = child.take_stdout()
    var text = alloc.vec.new<u8>()
    match take out { present(o) => { var r = o; let c = try r.read_to_end(text) }, none => { return 2 } }
    let st = try child.wait()
    if st.code() != present(0) { return 3 }
    if text.len() != 5usize || text[0usize] != 80u8 { return 4 }
    0
}

fn decimal(v: u32): List<u8> {
    var digits = alloc.vec.new<u8>()
    var x = v
    if x == 0u32 { digits.push(48u8) }
    while x > 0u32 { digits.push((48u32 + x % 10u32) as u8); x = x / 10u32 }
    var out = alloc.vec.new<u8>()
    var i = digits.len()
    while i > 0usize { i -= 1usize; let d = digits[i]; out.push(d) }
    out
}

fn parse(text: read [u8]): u16 {
    var v = 0u32
    var i = 0usize
    while i < text.len() { v = v * 10u32 + (text[i] - 48u8) as u32; i += 1usize }
    v as u16
}

fn client(port_text: read ffi.OsStr): i32 throws Error {
    let addr = std.net.socket_addr(std.net.localhost(), parse(port_text.as_bytes()))
    var s = try std.net.tcp_connect(addr)
    try s.set_read_timeout(present(from_millis(20000u64)))
    try s.write_all("ping".as_bytes())
    var buf = [0u8; 8]
    try s.read_exact(buf.split_at_mut(4usize).0)
    if buf[0usize] != 80u8 { return 1 }
    std.io.print("PONG\n")
    0
}

fn main(): i32 {
    let args = std.env.args()
    var mode = 0
    if args.len() > 2usize { mode = 1 }
    var r = 0
    if mode == 1 {
        let c = capture client(args[2usize].as_os_str())
        match take c { success(v) => { r = v }, failure(e) => { r = 100 } }
    } else {
        let c = capture serve()
        match take c { success(v) => { r = v }, failure(e) => { r = 100 } }
    }
    r
}
