use std::collections::HashMap;

fn seed() -> i64 { 12345i64 } // bench-edit-point

fn main() {
    let mut counts: HashMap<i32, i32> = HashMap::new();
    let mut state = seed();
    let mut index = 0;
    while index < 2000000 {
        state = (state * 1103515245i64 + 12345i64) % 2147483648i64;
        let key = ((state >> 8i64) % 100003i64) as i32;
        *counts.entry(key).or_insert(0) += 1;
        index += 1;
    }
    let mut checksum = 0i64;
    let mut key = 0;
    while key < 100003 {
        if let Some(count) = counts.get(&key) {
            checksum += (*count as i64) * ((key % 31) as i64 + 1i64);
        }
        key += 1;
    }
    std::process::exit(((checksum + counts.len() as i64) % 128i64) as i32);
}
