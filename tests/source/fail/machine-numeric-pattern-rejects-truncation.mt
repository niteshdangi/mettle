// expect-error: type 3:24 pattern literal is outside the u64 range

fn main(){match 1u64 { 18446744073709551616 => 0, _ => 1 }}
