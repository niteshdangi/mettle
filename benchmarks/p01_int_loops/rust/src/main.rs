fn seed() -> i32 { 12345 } // bench-edit-point

fn reduce(limit: i32) -> i32 {
    let mut state = seed();
    let mut index = 0;
    while index < limit {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        index += 1;
    }
    state & 127
}

fn main() {
    std::process::exit(reduce(268435456));
}
