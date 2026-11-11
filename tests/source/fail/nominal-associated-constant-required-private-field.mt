// expect-error: name 7:18 private or restricted field
pub module encapsulated {
    pub copy type Secret { field: usize }
    extend Secret { pub const VALUE: Secret = Secret(2usize) }
}
fn main(): i32 {
    let row: [u8;encapsulated.Secret.VALUE.field] = [3u8;2usize]
    0
}
