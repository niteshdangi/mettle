import alloc.arc
import alloc.rc
import core.convert.{From, TryFrom}
import core.iter.FromItems

type Counted {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}

// Shared slices move their elements in once: nothing is copied or dropped early.
fn main(): i32 {
    var drops = 0
    {
        let shared = rc.Rc<[Counted]>.(From<[Counted; 2]>).`from`(
            [Counted(core.ptr.from_mut(drops)), Counted(core.ptr.from_mut(drops))])
        if shared.get().len() != 2usize || drops != 0 { return 1 }
    }
    if drops != 2 { return 2 }
    {
        let atomic = arc.Arc<[Counted]>.(From<[Counted; 3]>).`from`(
            [Counted(core.ptr.from_mut(drops)), Counted(core.ptr.from_mut(drops)), Counted(core.ptr.from_mut(drops))])
        if atomic.get().len() != 3usize || drops != 2 { return 3 }
    }
    if drops != 5 { return 4 }

    let numbers = rc.Rc<[i32]>.(FromItems<i32>).from_iter([4, 5, 6])
    if numbers.get().len() != 3usize || numbers.get()[1usize] != 5 { return 5 }
    let empty = arc.Arc<[i32]>.(FromItems<i32>).from_iter(alloc.vec.new<i32>())
    if empty.get().len() != 0usize { return 6 }

    let exact = capture rc.Rc<[i32; 3], alloc.alloc.Global>.(TryFrom<rc.Rc<[i32], alloc.alloc.Global>>).try_from(numbers)
    match take exact {
        success(fixed) => { if fixed.get()[2usize] != 6 || fixed.strong_count() != 1usize { return 7 } },
        failure(_) => { return 8 }
    }
    let wrong = capture arc.Arc<[i32; 2], alloc.alloc.Global>.(TryFrom<arc.Arc<[i32], alloc.alloc.Global>>).try_from(empty)
    match take wrong {
        success(_) => { return 9 },
        failure(back) => { if back.get().len() != 0usize { return 10 } }
    }
    0
}
