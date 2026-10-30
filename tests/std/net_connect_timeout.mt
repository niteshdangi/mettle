import std.io.{Error, ErrorKind}
import std.net.{TcpStream, socket_addr, localhost, tcp_listen}
import std.time.{from_millis, now}

fn run(): i32 throws Error {
    var port = 0u16
    {
        let listener = try tcp_listen(socket_addr(localhost(), 0u16))
        port = (try listener.local_addr()).port
    }
    let started = now()
    let result = capture TcpStream.connect_timeout(
        socket_addr(localhost(), port), from_millis(200u64)
    )
    match take result {
        success(stream) => { return 1 },
        failure(error) => {
            if !error.kind().is(ErrorKind.ConnectionRefused) &&
                !error.kind().is(ErrorKind.TimedOut) { return 2 }
            if !started.elapsed().lt(from_millis(2000u64)) { return 3 }
        }
    }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
