// profiles: debug release
import core.clone.Clone
import core.iter.OwnedIterable
import std.panic.CatchResult

type Tracked {
    value: i32
    clones: ptr<mut usize>
    drops: ptr<mut usize>
    panic_on: usize
    drop { unsafe { *self.drops += 1usize } }
}

extend Tracked implements Clone {
    fn clone(): Tracked {
        unsafe {
            *self.clones += 1usize
            if self.panic_on != 0usize && *self.clones == self.panic_on {
                panic("array iterator clone")
            }
        }
        Tracked(self.value, self.clones, self.drops, self.panic_on)
    }
}

fn tracked(
    value: i32,
    clones: ptr<mut usize>,
    drops: ptr<mut usize>,
    panic_on: usize
): Tracked {
    Tracked(value, clones, drops, panic_on)
}

fn main(): i32 {
    var clones = 0usize
    var drops = 0usize
    let clone_count = core.ptr.from_mut(clones)
    let drop_count = core.ptr.from_mut(drops)
    {
        var source = [
            tracked(1, clone_count, drop_count, 0usize),
            tracked(2, clone_count, drop_count, 0usize),
            tracked(3, clone_count, drop_count, 0usize),
            tracked(4, clone_count, drop_count, 0usize)
        ].into_iter()
        match source.next() {
            present(item) => { if item.value != 1 { return 1 } },
            none => { return 2 }
        }
        match source.next_back() {
            present(item) => { if item.value != 4 { return 3 } },
            none => { return 4 }
        }
        var copied = source.clone()
        if clones != 2usize { return 5 }
        match source.next() {
            present(item) => { if item.value != 2 { return 6 } },
            none => { return 7 }
        }
        match source.next() {
            present(item) => { if item.value != 3 { return 8 } },
            none => { return 9 }
        }
        match copied.next() {
            present(item) => { if item.value != 2 { return 10 } },
            none => { return 11 }
        }
        match copied.next() {
            present(item) => { if item.value != 3 { return 12 } },
            none => { return 13 }
        }
        core.mem.drop(source)
        core.mem.drop(copied)
    }
    if drops != 6usize { return 14 }

    clones = 0usize
    drops = 0usize
    {
        var empty = [tracked(5, clone_count, drop_count, 0usize)].into_iter()
        match empty.next() {
            present(item) => { if item.value != 5 { return 15 } },
            none => { return 16 }
        }
        var empty_copy = empty.clone()
        if clones != 0usize || empty_copy.next().is_present() { return 17 }
        core.mem.drop(empty)
        core.mem.drop(empty_copy)
    }
    if drops != 1usize { return 18 }

    clones = 0usize
    drops = 0usize
    {
        var source = [
            tracked(6, clone_count, drop_count, 2usize),
            tracked(7, clone_count, drop_count, 2usize),
            tracked(8, clone_count, drop_count, 2usize)
        ].into_iter()
        match std.panic.catch_panic(fn(): Unit { let _ = source.clone() }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 19 }
        }
        if clones != 2usize || drops != 1usize { return 20 }
        core.mem.drop(source)
    }
    if drops != 4usize { return 21 }
    0
}
