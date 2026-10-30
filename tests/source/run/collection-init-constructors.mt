import alloc.alloc.Global
import alloc.vec.List
import alloc.hash_map.{Map, Set}
import alloc.string.String

fn main(): i32 {
    let first = List<i32>()
    let second = List<i32, Global>(allocator: Global())
    let map = Map<i32, i32>()
    let map_in = Map<i32, i32, Global>(allocator: Global())
    let set = Set<i32>()
    let set_in = Set<i32, Global>(allocator: Global())
    let text = String("ok")
    let other = String("ok", allocator: Global())
    if first.len() == 0usize && second.len() == 0usize &&
       map.len() == 0usize && map_in.len() == 0usize &&
       set.len() == 0usize && set_in.len() == 0usize &&
       text.as_text() == "ok" && other.as_text() == "ok" { 0 } else { 1 }
}
