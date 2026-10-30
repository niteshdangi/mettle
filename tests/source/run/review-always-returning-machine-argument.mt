
fn early():i32 {
    let pointer = core::ptr::from_ref({ return 7; 5i64 })
    0
}
fn main() { early() - 7 }
