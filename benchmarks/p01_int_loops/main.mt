fn seed(): i32 { 12345 } // bench-edit-point

fn reduce(limit: i32): i32 {
    var state = seed()
    var index = 0
    while index < limit {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        index += 1
    }
    state & 127
}

fn main(): i32 { reduce(268435456) }
