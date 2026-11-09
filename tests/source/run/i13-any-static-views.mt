// profiles: debug release
// Views over static data are Static, so Any applies to view-bearing types.
import core.any
import core.any.{Any, TypeId}
import core.cmp.PartialEq

fn id<T: Any>(value: read T): TypeId { T.(Any).type_id(value) }

static NUMBERS: [i32; 4] = [1, 2, 3, 4]

fn main(): i32 {
    let text: read core.text.Text from static = "a b"
    if id(read text.chars()) != any.type_id<core.text.Chars<region static>>() { return 1 }
    if id(read text.bytes()) != any.type_id<core.text.Bytes<region static>>() { return 2 }
    if id(read text.char_indices()) != any.type_id<core.text.CharIndices<region static>>() { return 3 }
    if id(read text.split_whitespace()) != any.type_id<core.text.SplitWhitespace<region static>>() { return 4 }
    if any.type_id<core.text.Split<region static>>() == any.type_id<core.text.Chars<region static>>() { return 5 }
    let numbers: read [i32] from static = read NUMBERS
    if id(read numbers.chunks(2usize)) != any.type_id<core.slice.SliceChunks<region static, i32>>() { return 6 }
    if id(read numbers.windows(2usize)) != any.type_id<core.slice.SliceWindows<region static, i32>>() { return 7 }
    if id(read numbers.iter()) != any.type_id<core.slice.SliceIter<region static, i32>>() { return 8 }
    let ids = [
        any.type_id<alloc.vec.Drain<region static, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.string.StringDrain<region static, alloc.alloc.Global>>(),
        any.type_id<alloc.vec_deque.DequeIter<region static, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.vec_deque.DequeIterMut<region static, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.vec_deque.DequeDrain<region static, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.hash_map.Iter<region static, i32, i32>>(),
        any.type_id<alloc.hash_map.IterMut<region static, i32, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.hash_map.Keys<region static, i32, i32>>(),
        any.type_id<alloc.hash_map.Values<region static, i32, i32>>(),
        any.type_id<alloc.hash_map.MapDrain<region static, i32, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.hash_map.SetDrain<region static, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.hash_map.Entry<region static, i32, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.btree.EntryIter<region static, i32, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.btree.IterMut<region static, i32, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.btree.Keys<region static, i32, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.btree.Values<region static, i32, i32, alloc.alloc.Global>>(),
        any.type_id<alloc.btree.Entry<region static, i32, i32, alloc.alloc.Global>>(),
        any.type_id<std.ffi.CStr<region static>>(),
        any.type_id<core.fmt.Message<region static>>(),
        any.type_id<core.future.Context<region static>>(),
        any.type_id<std.sync.mutex.MutexGuard<i32, region static>>()
    ]
    var i = 0usize
    while i < 21usize {
        var j = i + 1usize
        while j < 21usize {
            if ids[i] == ids[j] { return 9 }
            j += 1usize
        }
        i += 1usize
    }
    0
}
