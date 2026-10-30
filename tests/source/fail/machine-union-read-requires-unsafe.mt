// expect-error: unsafe 3:60 reading a union field requires unsafe
union Bits { integer: u32; real: f32 }
fn main() { let value = Bits(integer: 42u32); let result = value.real; 0 }
