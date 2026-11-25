import alloc.vec.List
import alloc.rc.LocalShared
import alloc.hash_map.Map
import alloc.vec_deque.Deque
import alloc.linked_list.LinkedList
import alloc.btree.SortedMap
import alloc.boxed.Heap

// Adds its id to a shared counter when dropped; each drop must happen exactly once.
type D { c: ptr<mut i32>; id: i32
    drop { unsafe { *self.c += self.id } } }

static mut ZERO_DROPS: usize = 0usize
type ZeroDrop { drop { unsafe { ZERO_DROPS += 1usize } } }

fn main(): i32 {
    var n = 0
    let c = core.ptr.from_mut(n)
    {
        var v = alloc.vec.new<D>()
        var i = 0
        while i < 50 { v.push(D(c, 1)); i += 1 }
        let x = v.remove(10usize)
        let y = v.swap_remove(0usize)
        if n != 0 { return 1 }
    }
    if n != 50 { return 2 }
    n = 0
    {
        var m = alloc.hash_map.new<i32, D>()
        var i = 0
        while i < 100 { let r = m.insert(i + 0, D(c, 1)); i += 1 }
        let r = m.insert(5, D(c, 1000))
        match r { present(_) => {}, none => { return 3 } }
        m.reserve(1024usize)
        m.shrink_to_fit()
        if n != 0 || m.get(5).or_panic().id != 1000 { return 4 }
        let gone = m.remove(7)
    }
    if n != 1100 { return 9 }
    {
        var zero = alloc.hash_map.new<Unit, ZeroDrop>()
        zero.insert((), ZeroDrop())
        zero.reserve(32usize)
        zero.shrink_to_fit()
        if !zero.get(()).is_present() || unsafe { ZERO_DROPS != 0usize } { return 11 }
    }
    if unsafe { ZERO_DROPS != 1usize } { return 12 }
    n = 0
    {
        var d = alloc.vec_deque.new<D>()
        var i = 0
        while i < 20 { d.push_back(D(c, 1)); d.push_front(D(c, 1)); i += 1 }
        let a = d.pop_front()
        let b = d.pop_back()
    }
    if n != 40 { return 5 }
    n = 0
    {
        var l = alloc.linked_list.new<D>()
        var i = 0
        while i < 10 { l.push_back(D(c, 1)); i += 1 }
    }
    if n != 10 { return 6 }
    n = 0
    {
        var t = alloc.btree.new<i32, D>()
        var i = 0
        while i < 10 { let r = t.insert(i + 0, D(c, 1)); i += 1 }
        let r = t.insert(3, D(c, 100))
    }
    if n != 110 { return 7 }
    n = 0
    {
        let b = alloc.boxed.new(D(c, 7))
        let r1 = alloc.rc.new(D(c, 9))
        let r2 = r1.retain()
    }
    if n != 16 { return 8 }
    0
}
