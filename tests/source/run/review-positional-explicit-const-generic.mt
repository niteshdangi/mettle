type Buffer<const N: usize> { values: [i32; N] }
fn value<const N: usize>(): usize { N }
fn first(buffer: Buffer<const { 2usize }>): i32 { buffer.values[0] }
fn main(): i32 {
    if value<const { 1usize + 1usize }>() == 2usize &&
       value<{ 3usize }>() == 3usize &&
       first(Buffer([42, 0])) == 42 { 0 } else { 1 }
}
