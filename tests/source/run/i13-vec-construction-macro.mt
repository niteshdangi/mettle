// profiles: debug release
import alloc.vec.{List, vec}
import core.clone.Clone
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
                panic("clone failed")
            }
        }
        Tracked(self.value, self.clones, self.drops, self.panic_on)
    }
}

fn make(evaluations: ptr<mut usize>, clones: ptr<mut usize>,
    drops: ptr<mut usize>, panic_on: usize): Tracked {
    unsafe {
        *evaluations += 1usize
        Tracked(*evaluations as i32, clones, drops, panic_on)
    }
}

fn main(): i32 {
    let empty: List<i32> = vec![]
    assert(empty.len() == 0usize && empty.capacity() == 0usize, "empty vector")
    let single = vec![42]
    assert(single.len() == 1usize && single[0usize] == 42, "single item")
    var evaluations = 0usize
    var clones = 0usize
    var drops = 0usize
    let e = core.ptr.from_mut(evaluations)
    let c = core.ptr.from_mut(clones)
    let d = core.ptr.from_mut(drops)
    {
        let values = vec![make(e, c, d, 0usize), make(e, c, d, 0usize), make(e, c, d, 0usize),]
        assert(values.len() == 3usize && values[0usize].value == 1 &&
            values[1usize].value == 2 && values[2usize].value == 3,
            "item expressions evaluate once in order and move without cloning")
    }
    assert(evaluations == 3usize && clones == 0usize && drops == 3usize, "list cleanup")
    evaluations = 0usize
    drops = 0usize
    {
        let values = vec![make(e, c, d, 0usize); 0usize]
        assert(values.is_empty() && values.capacity() == 0usize, "zero repetitions")
    }
    assert(evaluations == 1usize && clones == 0usize && drops == 1usize,
        "zero repetitions still evaluate and destroy the seed")
    evaluations = 0usize
    drops = 0usize
    {
        let values = vec![make(e, c, d, 0usize); 1usize]
        assert(values.len() == 1usize && values[0usize].value == 1, "one repetition")
    }
    assert(evaluations == 1usize && clones == 0usize && drops == 1usize, "seed is moved")
    evaluations = 0usize
    drops = 0usize
    {
        let values = vec![make(e, c, d, 0usize); 4usize]
        assert(values.len() == 4usize && values[0usize].value == 1 &&
            values[3usize].value == 1, "repeated payloads")
    }
    assert(evaluations == 1usize && clones == 3usize && drops == 4usize,
        "repetition clones only the extra elements")
    evaluations = 0usize
    clones = 0usize
    drops = 0usize
    match take std.panic.catch_panic(take fn(): Unit {
        let _ = vec![make(e, c, d, 2usize); 5usize]
    }) {
        CatchResult.Panicked(_) => {},
        _ => { return 1 }
    }
    assert(evaluations == 1usize && clones == 2usize && drops == 2usize,
        "clone panic drops the seed and only initialized copies")
    0
}
