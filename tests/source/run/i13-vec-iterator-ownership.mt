// profiles: debug release
import alloc.vec
import alloc.vec.IntoIter
import core.iter.{BidirectionalIterator, ExactSizeIterator, Iterator}

fn transferable<T: Transferable>() {}
fn shareable<T: Shareable>() {}

type Counted {
    value: i32
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

fn main(): i32 {
    transferable<IntoIter<i32>>()
    shareable<IntoIter<i32>>()

    var drain_drops = 0usize
    {
        var values = vec.new<Counted>()
        var i = 0usize
        while i < 5usize {
            values.push(Counted(i as i32, core.ptr.from_mut(drain_drops)))
            i += 1usize
        }
        {
            var drain = values.drain(1usize..4usize)
            if drain.len() != 3usize || drain.size_hint().0 != 3usize { return 1 }
            let _front = drain.next().unwrap()
            let _back = drain.next_back().unwrap()
            if drain.len() != 1usize || drain.as_slice()[0usize].value != 2 { return 2 }
            if drain_drops != 0usize { return 3 }
        }
        if values.len() != 2usize || values[0usize].value != 0 ||
            values[1usize].value != 4 {
            return 4
        }
        if drain_drops != 3usize { return 5 }
    }
    if drain_drops != 5usize { return 6 }

    var iter_drops = 0usize
    {
        var values = vec.new<Counted>()
        var i = 0usize
        while i < 4usize {
            values.push(Counted(i as i32, core.ptr.from_mut(iter_drops)))
            i += 1usize
        }
        var iterator: IntoIter<Counted> = values.into_iter()
        if iterator.len() != 4usize { return 7 }
        let _front = iterator.next().unwrap()
        let _back = iterator.next_back().unwrap()
        if iterator.len() != 2usize || iterator.size_hint().0 != 2usize { return 8 }
        if iter_drops != 0usize { return 9 }
    }
    if iter_drops != 4usize { return 10 }
    0
}
