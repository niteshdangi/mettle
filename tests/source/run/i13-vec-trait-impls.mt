// profiles: debug release
import alloc.vec
import alloc.vec.{List, IntoIter, Drain}
import alloc.boxed
import alloc.boxed.Box
import alloc.binary_heap
import alloc.binary_heap.BinaryHeap
import alloc.string
import alloc.vec_deque
import alloc.vec_deque.Deque
import core.borrow.{AsMut, AsRef, Borrow, BorrowMut}
import core.clone.Clone
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.convert.From
import core.default.Default
import core.fmt
import core.fmt.Debug
import core.hash.{Hash, Hasher, fnv1a}
import core.iter.{FromItems, Iterator, OwnedIterable, BidirectionalIterator}
import core.ops.{Deref, DerefMut}
import core.text.Text
import std.io.Writer

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn as_view<V: AsRef<[i32]>>(read value: V): read [i32] from value { V.(AsRef<[i32]>).as_ref(value) }

fn main(): i32 {
    var v = vec.new<i32>()
    v.push(1)
    v.push(2)
    v.push(3)

    let b: read [i32] = List<i32>.(Borrow<[i32]>).borrow(read v)
    if b.len() != 3usize { return 1 }
    var bm: mut [i32] = List<i32>.(BorrowMut<[i32]>).borrow_mut(mut v)
    bm[0usize] = 10
    if v[0usize] != 10 { return 2 }
    let asr: read [i32] = List<i32>.(AsRef<[i32]>).as_ref(read v)
    if asr[2usize] != 3 { return 3 }
    var asm: mut [i32] = List<i32>.(AsMut<[i32]>).as_mut(mut v)
    asm[1usize] = 20
    if v[1usize] != 20 { return 4 }

    let c = v.clone()
    if c != v || c.len() != 3usize { return 5 }
    let w = vec.new<i32>()
    if w == v || !(w < v) { return 6 }
    match c.cmp(read v) {
        Ordering.Equal => {},
        _ => { return 7 }
    }

    var hasher_a = fnv1a()
    v.hash(mut hasher_a)
    var hasher_b = fnv1a()
    let slice_view: read [i32] = v.as_slice()
    slice_view.hash(mut hasher_b)
    if hasher_a.finish() != hasher_b.finish() { return 9 }

    if !debug_is(read v, "[10, 20, 3]") { return 10 }
    if !debug_is(read w, "[]") { return 11 }

    let from_array = List<i32>.(From<[i32; 3]>).from([1, 2, 3])
    if from_array.len() != 3usize || from_array[2usize] != 3 { return 12 }
    let arr_view: read [i32] = from_array.as_slice()
    let from_slice = List<i32>.(From<read [i32]>).from(arr_view)
    if from_slice[1usize] != 2 { return 13 }
    let from_ref_array = List<i32>.(From<read [i32; 3]>).from(read [4, 5, 6])
    if from_ref_array[0usize] != 4 { return 14 }
    let bytes = List<u8>.(From<read Text>).from("ab")
    if bytes.len() != 2usize || bytes[1usize] != 98u8 { return 15 }
    var mutable_slice_source = [7, 8]
    let mutable_slice: mut [i32] = mut mutable_slice_source
    let from_mut_slice = List<i32>.(From<mut [i32]>).from(take mutable_slice)
    if from_mut_slice[1usize] != 8 { return 42 }
    var mutable_array_source = [9, 10]
    let mutable_array: mut [i32; 2] = mut mutable_array_source
    let from_mut_array = List<i32>.(From<mut [i32; 2]>).from(take mutable_array)
    if from_mut_array[0usize] != 9 { return 43 }

    let items = List<i32>.(FromItems<i32>).from_iter(c.clone().into_iter())
    if items[1usize] != 20 { return 16 }

    let range_view: read [i32] = read v[0usize..2usize]
    if range_view.len() != 2usize { return 17 }
    v[2usize] = 30
    if v[2usize] != 30 { return 18 }
    var sl: mut [i32] = List<i32>.(DerefMut).deref_mut(mut v)
    sl[0usize] = 11
    if v[0usize] != 11 { return 19 }
    let dv: read [i32] = List<i32>.(Deref).deref(read v)
    if dv.len() != 3usize { return 20 }

    var it = c.clone().into_iter()
    if it.len() != 3usize { return 21 }
    let it2 = it.clone()
    if it.next_back().or_panic() != 3 || it.next().or_panic() != 10 { return 22 }
    if it2.size_hint().0 != 3usize { return 23 }
    let view_it: read [i32] = IntoIter<i32>.(AsRef<[i32]>).as_ref(read it)
    if view_it.len() != 1usize { return 24 }
    if !debug_is(read it, "IntoIter([20])") { return 25 }

    var dr = vec.new<i32>()
    dr.push(1)
    dr.push(2)
    dr.push(3)
    {
        var drain = dr.drain(0usize..2usize)
        if !debug_is(read drain, "Drain([1, 2])") { return 26 }
        let dview: read [i32] = as_view(read drain)
        if dview.len() != 2usize || drain.as_slice()[0usize] != 1 { return 27 }
    }
    if dr.len() != 1usize || dr[0usize] != 3 { return 28 }
    let empty: IntoIter<i32> = IntoIter<i32>.(Default).default()
    if empty.len() != 0usize { return 29 }

    let parts = [List<i32>.(From<[i32; 2]>).from([1, 2]), List<i32>.(From<[i32; 1]>).from([3])]
    let cat: List<i32> = parts.concat()
    if cat.len() != 3usize || cat[2usize] != 3 { return 30 }
    let sep = [0, 0]
    let joined: List<i32> = parts.join(read sep)
    if joined.len() != 5usize || joined[2usize] != 0 || joined[4usize] != 3 { return 31 }

    if !needs_eq(read v) { return 32 }
    let as_mut_list = List<i32>.(AsMut<List<i32>>).as_mut(mut v)
    as_mut_list.push(77)
    if v.len() != 4usize || v[3usize] != 77 { return 33 }
    let from_string = List<u8>.(From<string.String>).from(string.from_text("cd"))
    if from_string[0usize] != 99u8 { return 34 }
    let from_box = List<i32>.(From<Box<[i32]>>).from(Box<[i32]>.(From<[i32; 2]>).from([21, 22]))
    if from_box[1usize] != 22 { return 35 }
    var pile = binary_heap.new<i32>()
    pile.push(4)
    let from_heap = List<i32>.(From<BinaryHeap<i32>>).from(pile)
    if from_heap.len() != 1usize || from_heap[0usize] != 4 { return 36 }
    var deque = vec_deque.new<i32>()
    deque.push_back(5)
    let from_deque = List<i32>.(From<Deque<i32>>).from(deque)
    if from_deque[0usize] != 5 { return 37 }
    var owned_iter = List<i32>.(From<[i32; 3]>).from([1, 2, 3]).into_iter()
    let _skipped = owned_iter.next()
    if owned_iter.as_slice()[0usize] != 2 { return 38 }
    owned_iter.as_mut_slice()[0usize] = 5
    if owned_iter.as_slice()[0usize] != 5 { return 39 }
    var sink = vec.new<u8>()
    match capture List<u8>.(Writer).write_all(mut sink, read bytes) {
        success(_) => {},
        failure(_) => { return 40 }
    }
    if sink.len() != 2usize || sink[1usize] != 98u8 { return 41 }
    0
}

fn needs_eq<T: Eq>(read value: T): bool { true }
