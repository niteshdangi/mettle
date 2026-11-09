import std.io.{Error, Writer}
import std.net.TcpStream

fn write_later(read stream: TcpStream): bool {
    var writer = match take capture stream.try_clone() {
        success(value) => value,
        failure(_) => { return false }
    }
    std.time.sleep(std.time.from_millis(20u64))
    (capture writer.write_all("x".as_bytes())).is_success()
}

fn run(): i32 throws Error {
    let listener = try std.net.tcp_listen(std.net.socket_addr(std.net.localhost(), 0u16))
    let client = try std.net.tcp_connect(try listener.local_addr())
    let pair = try listener.accept()
    let server = pair.0
    let writer = std.thread.spawn(take fn(): bool { write_later(server) })
    // This used to narrow to zero and return before the delayed write.
    if !try client.wait_readable(std.time.from_millis(4294967296u64)) { return 1 }
    match take capture writer.join() { success(ok) => { if !ok { return 2 } }, failure(_) => { return 3 } }
    0
}

fn main(): i32 { match take capture run() { success(code) => code, failure(_) => 4 } }
