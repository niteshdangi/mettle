import alloc.boxed
import alloc.boxed.Heap
import alloc.vec
import alloc.vec.List
import core.convert.{From, TryFrom}

fn main(): i32 {
    var items = vec.new<i32>()
    items.push(1)
    items.push(2)
    let array = match [i32; 2].(TryFrom<List<i32>>).try_from(items) {
        success(values) => values,
        failure(returned) => { return 1 }
    }
    if array[0usize] != 1 || array[1usize] != 2 { return 2 }

    var wrong = vec.new<i32>()
    wrong.push(9)
    match [i32; 2].(TryFrom<List<i32>>).try_from(wrong) {
        success(values) => { return 3 },
        failure(returned) => { if returned.len() != 1usize { return 4 } }
    }

    let slice = Heap<[i32]>.(From<[i32; 3]>).from([4, 5, 6])
    let list = slice.into_vec()
    if list.len() != 3usize || list.as_slice()[2usize] != 6 { return 5 }
    0
}
