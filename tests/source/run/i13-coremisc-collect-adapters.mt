// profiles: debug release

import core.iter
import core.iter.{ExtendItems, FromItems, Iterator, OwnedIterable}
import core.default.Default

fn default_of<T: Default>(): T { T.(Default).default() }

type EmptyRefs<region r> {}
extend<region r> EmptyRefs<region r> implements Iterator {
    type Item = read i32 from r
    mut fn next(): (read i32 from r)? { none }
}
extend<region r> EmptyRefs<region r> implements Default {
    static fn default(): EmptyRefs<region r> { EmptyRefs() }
}

type NoDefault {}
extend NoDefault implements Iterator {
    type Item = i32
    mut fn next(): i32? { none }
}

type Collected { sum: i32; count: usize }
extend Collected implements FromItems<i32> {
    static fn from_iter<I: OwnedIterable<Item = i32>>(take items: I): Collected {
        var iter = I.(OwnedIterable).into_iter(items)
        var sum = 0i32
        var count = 0usize
        while true {
            match take iter.next() {
                present(value) => { sum += value; count += 1usize },
                none => { break }
            }
        }
        Collected(sum, count)
    }
}
extend Collected implements ExtendItems<i32> {
    mut fn extend<I: OwnedIterable<Item = i32>>(take items: I): Unit {
        var iter = I.(OwnedIterable).into_iter(items)
        while true {
            match take iter.next() {
                present(value) => { self.sum += value; self.count += 1usize },
                none => { break }
            }
        }
    }
}

fn default_cloned<region r>(read anchor: i32 from r): i32? {
    let _ = anchor
    var cloned: iter.Cloned<region r, i32, EmptyRefs<region r>> = default_of()
    cloned.next()
}

fn default_copied<region r>(read anchor: i32 from r): i32? {
    let _ = anchor
    var copied: iter.Copied<region r, i32, EmptyRefs<region r>> = default_of()
    copied.next()
}

fn main(): i32 {
    let optional: Collected? = iter.range(1i32, 4i32).map(fn(take value: i32): i32? { present(value) }).collect()
    match optional {
        present(values) => {
            if values.count != 3usize || values.sum != 6 { return 1 }
        },
        none => { return 1 }
    }

    let missing: Collected? = iter.range(1i32, 5i32).map(fn(take value: i32): i32? { if value == 3 { none } else { present(value) } }).collect()
    if missing.is_present() { return 2 }

    let outcome: (Outcome<Collected, i32>) = iter.range(1i32, 4i32).map(fn(take value: i32): (Outcome<i32, i32>) { success(value) }).collect()
    match outcome {
        success(values) => {
            if values.count != 3usize || values.sum != 6 { return 3 }
        },
        failure(_) => { return 3 }
    }

    let failed: (Outcome<Collected, i32>) = iter.range(1i32, 5i32).map(fn(take value: i32): (Outcome<i32, i32>) {
            if value == 3 { failure(9i32) } else { success(value) }
        }).collect()
    match failed {
        success(_) => { return 4 },
        failure(error) => { if error != 9 { return 4 } }
    }

    let anchor = 1i32
    if default_cloned(read anchor).is_present() { return 5 }
    if default_copied(read anchor).is_present() { return 6 }
    var flattened: iter.Flatten<NoDefault, iter.Empty<NoDefault>> = default_of()
    if flattened.next().is_present() { return 7 }
    var reversed: iter.Reversed<iter.Range<i32>> = default_of()
    if reversed.next().is_present() { return 8 }
    var extended = Collected(0i32, 0usize)
    extended.extend(iter.range(1i32, 4i32))
    if extended.sum != 6 || extended.count != 3usize { return 9 }
    0
}
