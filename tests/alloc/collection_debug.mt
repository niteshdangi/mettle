import alloc.binary_heap;
import alloc.btree;
import alloc.hash_map;
import alloc.linked_list;
import alloc.string.String;
import alloc.vec;
import alloc.vec.Vec;
import alloc.vec_deque;
import alloc.boxed;
import core.clone.Clone;
import alloc.rc;
import core.fmt;
import core.fmt.Debug;

fn render<T: Debug>(value: read T, pretty: bool): String {
    var out = alloc.string.new()
    var options = fmt.spec()
    options.alternate = pretty
    {
        var f = fmt.formatter(mut out, options)
        match capture T.(Debug).fmt(value, mut f) { success(u) => {}, failure(e) => { return alloc.string.new() } }
    }
    out
}
fn is(value: read String, expected: read Text): bool { value.as_text() == expected }

fn main(): i32 {
    var v = vec.new<i32>()
    if !is(render(v, false), "[]") || !is(render(v, true), "[]") { return 1 }
    v.push(1); v.push(2)
    if !is(render(v, false), "[1, 2]") { return 2 }
    if !is(render(v, true), "[\n    1,\n    2,\n]") { return 3 }

    var nested = vec.new<Vec<i32>>()
    nested.push(vec.new<i32>())
    nested.push(v.clone())
    if !is(render(nested, false), "[[], [1, 2]]") { return 4 }
    if !is(render(nested, true), "[\n    [],\n    [\n        1,\n        2,\n    ],\n]") { return 5 }

    var d = vec_deque.new<i32>()
    d.push_back(2); d.push_front(1)
    if !is(render(d, false), "[1, 2]") { return 6 }
    var l = linked_list.new<i32>()
    l.push_back(3); l.push_back(4)
    if !is(render(l, false), "[3, 4]") || !is(render(l, true), "[\n    3,\n    4,\n]") { return 7 }
    var h = binary_heap.new<i32>()
    h.push(1)
    if !is(render(h, false), "[1]") { return 8 }

    var m = hash_map.new<i32, i32>()
    if !is(render(m, false), "{}") || !is(render(m, true), "{}") { return 9 }
    m.insert(1, 10); m.insert(2, 20)
    if !is(render(m, false), "{1: 10, 2: 20}") { return 10 }
    if !is(render(m, true), "{\n    1: 10,\n    2: 20,\n}") { return 11 }
    var s = hash_map.set_new<i32>()
    s.insert(5)
    if !is(render(s, false), "{5}") || !is(render(s, true), "{\n    5,\n}") { return 12 }

    var b = btree.new<i32, String>()
    b.insert(2, alloc.string.from_text("b"))
    b.insert(1, alloc.string.from_text("a"))
    if !is(render(b, false), "{1: \"a\", 2: \"b\"}") { return 13 }
    var bs = btree.set_new<i32>()
    bs.insert(9); bs.insert(8)
    if !is(render(bs, false), "{8, 9}") { return 14 }

    var inner = vec.new<btree.BTreeSet<i32>>()
    inner.push(bs)
    if !is(render(inner, true), "[\n    {\n        8,\n        9,\n    },\n]") { return 15 }
    if !is(render(boxed.new(v), false), "[1, 2]") { return 16 }
    if !is(render(rc.new(d), false), "[1, 2]") { return 17 }
    let some: i32? = present(3)
    let nothing: i32? = none
    if !is(render(some, false), "present(3)") || !is(render(nothing, false), "none") { return 18 }
    let good: i32 throws i32 = success(4)
    let bad: i32 throws i32 = failure(5)
    if !is(render(good, false), "success(4)") || !is(render(bad, false), "failure(5)") { return 19 }
    if !is(render((7,), false), "(7,)") || !is(render((1, true, 'x'), false), "(1, true, 'x')") { return 20 }
    if !is(render((1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12), false), "(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)") { return 21 }
    if !is(render((1, 2), true), "(\n    1,\n    2,\n)") { return 22 }
    if !is(render([1, 2, 3], false), "[1, 2, 3]") || !is(render([some, nothing], false), "[present(3), none]") { return 23 }
    0
}
