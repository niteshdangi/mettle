// expect-error: alignment 15:5 unaligned storage cannot form an ordinary view
import core.ops.Add

copy type Word { value: i32 }
extend Word implements Add<Word> {
    type Output = i32
    fn add(read rhs: Word): i32 { self.value + rhs.value }
}

@packed(1)
copy type Packed { tag: u8; word: Word }

fn main(): i32 {
    let value = Packed(0u8, Word(21))
    value.word + Word(21) - 42
}
