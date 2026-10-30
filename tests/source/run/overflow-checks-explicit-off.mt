// profiles: debug
// flags: --overflow-checks off
fn main() { let x = 2147483647; if x + 1 < 0 { 0 } else { 1 } }
