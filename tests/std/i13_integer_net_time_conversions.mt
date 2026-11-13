import core.convert.From
import core.ops.Mul
import std.net.{Ipv4Addr, Ipv6Addr}
import std.time.{Duration, from_millis}

fn main(): i32 {
    let v4 = Ipv4Addr.from_bits(0x7f000001u32)
    if u32.(From<Ipv4Addr>).from(v4) != 0x7f000001u32 { return 1 }
    let v6 = Ipv6Addr.from_bits(0x20010db8000000000000000000000001u128)
    if u128.(From<Ipv6Addr>).from(v6) != 0x20010db8000000000000000000000001u128 { return 2 }
    if !u32.(Mul<Duration>).mul(3u32, from_millis(250u64)).same(from_millis(750u64)) { return 3 }
    0
}
