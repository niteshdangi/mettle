// expect-error: ownership 9:5 live read loan
import core.iter.Iterator
import std.io.Error
import std.net.ToSocketAddrs

fn example(): Unit throws Error {
    var input = [std.net.socket_addr(std.net.localhost(), 0u16)]
    var addresses = try input.to_socket_addrs()
    input[0usize] = std.net.socket_addr(std.net.localhost(), 1u16)
    let _ = addresses.next()
}

fn main(): i32 { 0 }
