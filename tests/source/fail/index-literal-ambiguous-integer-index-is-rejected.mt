// expect-error: type 18:8 unsatisfied interface obligation
// With more than one integer Index implementation an unsuffixed index is not
// guessed; it keeps the default literal type and the obligation fails.
import core.ops.Index

type Pair { values: [i32; 2] }
extend Pair implements Index<u8> {
    type Output = i32
    fn index(read index: u8): read i32 from self { read self.values[index as usize] }
}
extend Pair implements Index<u16> {
    type Output = i32
    fn index(read index: u16): read i32 from self { read self.values[index as usize] }
}

fn main(): i32 {
    let pair = Pair([1, 2])
    if pair[0] == 1 { 0 } else { 1 }
}
