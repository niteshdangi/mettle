import alloc.vec_deque
import alloc.linked_list
import core.iter.Iterator

type Item {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    var drops = 0
    {
        var deque = vec_deque.new<Item>()
        deque.push_back(Item(core.ptr.from_mut(drops), 1))
        deque.push_back(Item(core.ptr.from_mut(drops), 2))
        deque.push_back(Item(core.ptr.from_mut(drops), 3))
        var total = 0
        for item in take deque { total += item.value }
        if total != 6 || drops != 3 { return 1 }
    }
    if drops != 3 { return 2 }

    drops = 0
    {
        var deque = vec_deque.new<Item>()
        deque.push_back(Item(core.ptr.from_mut(drops), 1))
        deque.push_back(Item(core.ptr.from_mut(drops), 2))
        deque.push_back(Item(core.ptr.from_mut(drops), 3))
        {
            var items = deque.into_iter()
            match take items.next() {
                present(item) => { if item.value != 1 { return 3 } },
                none => { return 4 }
            }
        }
        if drops != 3 { return 5 }
    }

    drops = 0
    {
        var list = linked_list.new<Item>()
        list.push_back(Item(core.ptr.from_mut(drops), 4))
        list.push_back(Item(core.ptr.from_mut(drops), 5))
        list.push_back(Item(core.ptr.from_mut(drops), 6))
        var total = 0
        for item in take list { total += item.value }
        if total != 15 || drops != 3 { return 6 }
    }
    if drops != 3 { return 7 }

    drops = 0
    {
        var list = linked_list.new<Item>()
        list.push_back(Item(core.ptr.from_mut(drops), 4))
        list.push_back(Item(core.ptr.from_mut(drops), 5))
        list.push_back(Item(core.ptr.from_mut(drops), 6))
        {
            var items = list.into_iter()
            match take items.next() {
                present(item) => { if item.value != 4 { return 8 } },
                none => { return 9 }
            }
        }
        if drops != 3 { return 10 }
    }
    0
}
