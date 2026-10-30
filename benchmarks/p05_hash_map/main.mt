import alloc.hash_map;

fn seed(): i64 { 12345i64 } // bench-edit-point

fn main(): i32 {
    var counts = hash_map.new<i32, i32>()
    var state = seed()
    var index = 0
    while index < 2000000 {
        state = (state * 1103515245i64 + 12345i64) % 2147483648i64
        let key = ((state >> 8i64) % 100003i64) as i32
        var current = 0
        match counts.get(key) {
            present(count) => { current = *count },
            none => {}
        }
        counts.insert(key, current + 1)
        index += 1
    }
    var checksum = 0i64
    var key = 0
    while key < 100003 {
        match counts.get(key) {
            present(count) => { checksum += ((*count) as i64) * ((key % 31) as i64 + 1i64) },
            none => {}
        }
        key += 1
    }
    ((checksum + counts.len() as i64) % 128i64) as i32
}
