import core.iter.Iterator

type Guard {
    count: ptr<mut i32>
    drop { unsafe { *self.count += 1 } }
}
type Once {
    value: i32
    count: ptr<mut i32>
    drop { unsafe { *self.count += 1 } }
}
extend Once implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.value == 0 { none } else {
            let value = self.value
            self.value = 0
            present(value)
        }
    }
}

fn main(): i32 {
    var guards = 0
    var iterators = 0
    var attempts = 0
    var total = 0
    let stop = true
    for item in {
        let _guard = Guard(core.ptr.from_mut(guards))
        if stop { break }
        Once(99, core.ptr.from_mut(iterators))
    } {
        total += item
    }
    if guards != 1 || iterators != 0 || total != 0 { return 1 }
    for item in {
        let _guard = Guard(core.ptr.from_mut(guards))
        attempts += 1
        if attempts < 2 { continue }
        Once(5, core.ptr.from_mut(iterators))
    } {
        total += item
    }
    if guards == 3 && iterators == 1 && attempts == 2 && total == 5 {
        0
    } else { 2 }
}
