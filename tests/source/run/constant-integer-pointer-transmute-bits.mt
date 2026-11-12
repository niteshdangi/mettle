const fn from_bits(value: isize): ptr<read u8> {
    unsafe { core.mem.transmute<ptr<read u8>>(value) }
}

const NEGATIVE: ptr<read u8> = from_bits(-42isize)
const ALL_BITS: ptr<read u8> = from_bits(-1isize)

fn main() {
    if NEGATIVE == from_bits(-42isize) && NEGATIVE.addr() == (-42isize as usize) &&
       ALL_BITS == from_bits(-1isize) && ALL_BITS.addr() == (-1isize as usize) &&
       from_bits(0isize).is_null() && from_bits(42isize).addr() == 42usize {
        0
    } else {
        1
    }
}
