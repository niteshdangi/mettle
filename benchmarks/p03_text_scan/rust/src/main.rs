fn seed() -> u64 { 12345u64 } // bench-edit-point

fn generate(size: usize) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(size);
    let mut state = seed();
    let mut index = 0usize;
    while index < size {
        state = (state * 1103515245u64 + 12345u64) % 2147483648u64;
        let pick = (state >> 16u64) % 32u64;
        let mut byte = 97u8 + (pick % 26u64) as u8;
        if pick < 6u64 {
            byte = 32u8;
        }
        if pick == 6u64 {
            byte = 10u8;
        }
        bytes.push(byte);
        index += 1usize;
    }
    bytes
}

fn main() {
    let bytes = generate(33554432usize);
    let mut words = 0u64;
    let mut lines = 0u64;
    let mut vowels = 0u64;
    let mut inside = false;
    let mut index = 0usize;
    while index < bytes.len() {
        let byte = bytes[index];
        let space = byte == 32u8 || byte == 10u8;
        if byte == 10u8 {
            lines += 1u64;
        }
        if !space && !inside {
            words += 1u64;
        }
        if byte == 97u8 || byte == 101u8 || byte == 105u8 || byte == 111u8 || byte == 117u8 {
            vowels += 1u64;
        }
        inside = !space;
        index += 1usize;
    }
    std::process::exit(((words * 31u64 + lines * 7u64 + vowels) % 127u64) as i32);
}
