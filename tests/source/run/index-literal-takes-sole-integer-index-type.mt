// profiles: debug release
// An unsuffixed integer index takes the integer type of the receiver's only
// integer Index implementation: List and Deque index by usize, a user type
// indexing by i32 keeps i32.
import alloc.vec
import alloc.vec_deque
import core.ops.{Index, IndexMut}

type Grid { cells: [i32; 4] }
extend Grid implements Index<i32> {
    type Output = i32
    fn index(index: read i32): read i32 from self { read self.cells[index as usize] }
}

fn main(): i32 {
    var list = vec.new<i32>()
    list.push(10)
    list.push(20)
    list.push(30)
    if list[0] != 10 || list[2] != 30 { return 1 }
    list[1] = 25
    if list[1] != 25 { return 2 }
    var deque = vec_deque.new<i32>()
    deque.push_back(4)
    deque.push_front(3)
    if deque[0] != 3 || deque[1] != 4 { return 3 }
    let grid = Grid([7, 8, 9, 10])
    if grid[3] != 10 { return 4 }
    0
}
