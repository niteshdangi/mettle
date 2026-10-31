// Iteration. The compiler recognizes `Iterator`, `OwnedIterable`, `Iterable`
// and `MutableIterable` by canonical path for `for` loops. Adapters are lazy: they
// pull from the wrapped iterator only when `next` is called, and consuming
// methods stop at the first decisive item.
import super.cmp.Ord
import super.option
import super.cmp.Ordering
import super.clone.Clone

pub interface Iterator: Sized {
    type Item;
    mut fn next(): Self.Item?;

    // Bounds on the remaining length: `(lower, upper)`; `upper` is none when unknown.
    fn size_hint(): (usize, usize?) { (0usize, none) }

    mut fn count(): usize {
        var total = 0usize
        while true {
            match take self.next() { present(item) => { total += 1usize }, none => { break } }
        }
        total
    }
    take fn last(): Self.Item? {
        var remaining = self
        var result: Self.Item? = none
        while true {
            match take remaining.next() { present(item) => { result = present(item) }, none => { break } }
        }
        result
    }
    // Consumes `n` items first; the item after them is returned.
    mut fn nth(n: usize): Self.Item? {
        var skipped = 0usize
        while skipped < n {
            match take self.next() { present(item) => { skipped += 1usize }, none => { return none } }
        }
        self.next()
    }
    mut fn fold<B, F: fn(take B, take Self.Item): B>(start: take B, f: take F): B {
        var accumulator = start
        while true {
            match take self.next() {
                present(item) => { accumulator = f(take accumulator, item) },
                none => { break }
            }
        }
        accumulator
    }
    mut fn for_each<F: fn(take Self.Item): Unit>(f: take F): Unit {
        while true {
            match take self.next() { present(item) => { f(item) }, none => { break } }
        }
    }
    // Stops at the first item for which `test` holds.
    mut fn any<F: fn(take Self.Item): bool>(test: take F): bool {
        while true {
            match take self.next() {
                present(item) => { if test(item) { return true } },
                none => { break }
            }
        }
        false
    }
    // Stops at the first item for which `test` fails.
    mut fn all<F: fn(take Self.Item): bool>(test: take F): bool {
        while true {
            match take self.next() {
                present(item) => { if !test(item) { return false } },
                none => { break }
            }
        }
        true
    }
    mut fn find<F: fn(read Self.Item): bool>(test: take F): Self.Item? {
        while true {
            match take self.next() {
                present(item) => { if test(read item) { return present(item) } },
                none => { break }
            }
        }
        none
    }
    mut fn position<F: fn(take Self.Item): bool>(test: take F): usize? {
        var index = 0usize
        while true {
            match take self.next() {
                present(item) => {
                    if test(item) { return present(index) }
                    index += 1usize
                },
                none => { break }
            }
        }
        none
    }
    mut fn find_map<B, F: fn(take Self.Item): B?>(f: take F): B? {
        while true {
            match take self.next() {
                present(item) => { match take f(item) { present(found) => { return present(found) }, none => {} } },
                none => { break }
            }
        }
        none
    }
    mut fn reduce<F: fn(take Self.Item, take Self.Item): Self.Item>(f: take F): Self.Item? {
        var accumulator = self.next()
        while true {
            match take self.next() {
                present(item) => {
                    match take accumulator {
                        present(value) => { accumulator = present(f(value, item)) },
                        none => { accumulator = present(item) }
                    }
                },
                none => { break }
            }
        }
        accumulator
    }

    take fn map<B, F: fn(take Self.Item): B>(f: take F): Mapped<B, Self, F> { Mapped(self, f, Phantom<B>()) }
    take fn filter<F: fn(read Self.Item): bool>(test: take F): Filtered<Self, F> { Filtered(self, test) }
    take fn filter_map<B, F: fn(take Self.Item): B?>(f: take F): FilterMapped<B, Self, F> {
        FilterMapped(self, f, Phantom<B>())
    }
    take fn map_while<B, F: fn(take Self.Item): B?>(f: take F): MappedWhile<B, Self, F> {
        MappedWhile(self, f, Phantom<B>())
    }
    take fn flat_map<U: Iterator, F: fn(take Self.Item): U>(f: take F): FlatMapped<Self, U, F> {
        FlatMapped(self, none, f)
    }
    take fn enumerate(): Enumerated<Self> { Enumerated(self, 0usize) }
    take fn zip<U: Iterator>(other: take U): Zipped<Self, U> { Zipped(self, other) }
    take fn chain<U: Iterator>(other: take U): Chained<Self, U> { Chained(self, present(other), true) }
    take fn take_n(n: usize): Limited<Self> { Limited(self, n) }
    take fn skip(n: usize): Skipped<Self> { Skipped(self, n) }
    take fn take_while<F: fn(read Self.Item): bool>(test: take F): TakenWhile<Self, F> { TakenWhile(self, test, false) }
    take fn skip_while<F: fn(read Self.Item): bool>(test: take F): SkippedWhile<Self, F> { SkippedWhile(self, test, false) }
    // `step` must be nonzero; the first item is always produced.
    take fn step_by(step: usize): Stepped<Self> { Stepped(self, step, true) }
    take fn peekable(): Peekable<Self> { Peekable(self, none, false) }
    take fn inspect<F: fn(read Self.Item): Unit>(f: take F): Inspected<Self, F> { Inspected(self, f) }
    take fn fuse(): Fused<Self> { Fused(self, false) }
    take fn cycle(): Cycled<Self> where Self: Clone {
        let original = self.clone()
        Cycled(original, self, false, false)
    }
    take fn collect<C: FromItems<Self.Item>>(): C { C.(FromItems<Self.Item>).from_iter(self) }
}

// Collections that can be built from, or grown by, a sequence of owned items.
pub interface FromItems<T>: Sized {
    static fn from_iter<I: OwnedIterable<Item = T>>(items: take I): Self;
}
pub interface ExtendItems<T> {
    mut fn extend<I: OwnedIterable<Item = T>>(items: take I): Unit;
}
// `let v: List<i32> = collect(items)`.
pub fn collect<T, I: OwnedIterable<Item = T>, C: FromItems<T>>(items: take I): C {
    C.(FromItems<T>).from_iter(items)
}

pub fn chain<T, A: Iterator<Item = T>, B: Iterator<Item = T>>(first: take A, second: take B): Chained<A, B> {
    Chained(first, present(second), true)
}
pub fn zip<A: Iterator, B: Iterator>(first: take A, second: take B): Zipped<A, B> {
    Zipped(first, second)
}

// The iterator of an owned `for` source; async loops keep it in their state.
pub fn into_iterator<T: OwnedIterable>(items: take T): T.IntoIter {
    T.(OwnedIterable).into_iter(items)
}

// Iterators that can also yield from the back.
pub interface BidirectionalIterator: Iterator {
    mut fn next_back(): Self.(Iterator).Item?;
    mut fn nth_back(n: usize): Self.(Iterator).Item? {
        var skipped = 0usize
        while skipped < n {
            match take self.next_back() {
                present(item) => { skipped += 1usize },
                none => { return none }
            }
        }
        self.next_back()
    }
    mut fn rfind<F: fn(read Self.(Iterator).Item): bool>(test: take F): Self.(Iterator).Item? {
        while true {
            match take self.next_back() {
                present(item) => { if test(read item) { return present(item) } },
                none => { break }
            }
        }
        none
    }
    mut fn rposition<F: fn(take Self.(Iterator).Item): bool>(test: take F): usize? {
        while true {
            match take self.next_back() {
                present(item) => {
                    if test(item) {
                        var index = 0usize
                        while true {
                            match take self.next() {
                                present(_) => { index += 1usize },
                                none => { break }
                            }
                        }
                        return present(index)
                    }
                },
                none => { return none }
            }
        }
        none
    }
    mut fn rfold<B, F: fn(take B, take Self.(Iterator).Item): B>(start: take B, f: take F): B {
        var accumulator = start
        while true {
            match take self.next_back() {
                present(item) => { accumulator = f(take accumulator, item) },
                none => { break }
            }
        }
        accumulator
    }
    take fn rev(): Reversed<Self> { Reversed(self) }
}

pub interface OwnedIterable: Sized {
    type Item;
    type IntoIter: Iterator<Item = Self.Item>;
    fn into_iter(receiver self: take Self): Self.IntoIter;
}

// Borrowing iteration; the iterator is tied to the borrow of the receiver
// through the family region `r`, so `for x in read c` yields `read Item from c`,
// `for x in mut c` yields `mut Item from c`, and generic code can call `next`
// on `c.iter()`.
pub interface Iterable {
    type Item;
    type Iter<region r>: Iterator<Item = read Self.Item from r>;
    fn iter<region r>(receiver self: read Self from r): Self.Iter<region r>;
}

pub interface MutableIterable {
    type Item;
    type IterMut<region r>: Iterator<Item = mut Self.Item from r>;
    fn iter_mut<region r>(receiver self: mut Self from r): Self.IterMut<region r>;
}

// Every iterator is trivially its own OwnedIterable.
extend<I: Iterator> I implements OwnedIterable {
    type Item = I.Item
    type IntoIter = I
    fn into_iter(receiver self: take Self): I { self }
}

pub type Phantom<T> {}

pub type Mapped<B, I, F> { iter: I; f: F; result: Phantom<B> }
extend<B, I: Iterator, F: fn(take I.Item): B> Mapped<B, I, F> implements Iterator {
    type Item = B
    mut fn next(): B? {
        match take self.iter.next() { present(item) => present(self.f(item)), none => none }
    }
}
extend<B, I: Iterator + BidirectionalIterator, F: fn(take I.(Iterator).Item): B> Mapped<B, I, F> implements BidirectionalIterator {
    mut fn next_back(): B? {
        match take self.iter.next_back() { present(item) => present(self.f(item)), none => none }
    }
}

pub type Filtered<I, F> { iter: I; test: F }
extend<I: Iterator, F: fn(read I.Item): bool> Filtered<I, F> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? {
        while true {
            match take self.iter.next() {
                present(item) => { if self.test(read item) { return present(item) } },
                none => { break }
            }
        }
        none
    }
}
extend<I: Iterator + BidirectionalIterator, F: fn(read I.(Iterator).Item): bool> Filtered<I, F> implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? {
        while true {
            match take self.iter.next_back() {
                present(item) => { if self.test(read item) { return present(item) } },
                none => { break }
            }
        }
        none
    }
}

pub type FilterMapped<B, I, F> { iter: I; f: F; result: Phantom<B> }
extend<B, I: Iterator, F: fn(take I.Item): B?> FilterMapped<B, I, F> implements Iterator {
    type Item = B
    mut fn next(): B? {
        while true {
            match take self.iter.next() {
                present(item) => { match take self.f(item) { present(found) => { return present(found) }, none => {} } },
                none => { break }
            }
        }
        none
    }
}
extend<B, I: Iterator + BidirectionalIterator, F: fn(take I.(Iterator).Item): B?> FilterMapped<B, I, F> implements BidirectionalIterator {
    mut fn next_back(): B? {
        while true {
            match take self.iter.next_back() {
                present(item) => {
                    match take self.f(item) {
                        present(found) => { return present(found) },
                        none => {}
                    }
                },
                none => { break }
            }
        }
        none
    }
}

pub type MappedWhile<B, I, F> { iter: I; f: F; result: Phantom<B> }
extend<B, I: Iterator, F: fn(take I.Item): B?> MappedWhile<B, I, F> implements Iterator {
    type Item = B
    mut fn next(): B? {
        match take self.iter.next() {
            present(item) => self.f(item),
            none => none
        }
    }
}

pub type FlatMapped<O, U, F> { outer: O; inner: U?; f: F }
extend<O: Iterator, U: Iterator, F: fn(take O.Item): U> FlatMapped<O, U, F> implements Iterator {
    type Item = U.Item
    mut fn next(): U.Item? {
        while true {
            match mut self.inner {
                present(inner) => match inner.next() {
                    present(item) => { return present(item) },
                    none => { self.inner = none }
                },
                none => {}
            }
            match take self.outer.next() {
                present(item) => { self.inner = present(self.f(item)) },
                none => { return none }
            }
        }
        none
    }
}
extend<O: Iterator + BidirectionalIterator, U: Iterator + BidirectionalIterator, F: fn(take O.Item): U> FlatMapped<O, U, F> implements BidirectionalIterator {
    mut fn next_back(): U.Item? {
        while true {
            match mut self.inner {
                present(inner) => match inner.next_back() {
                    present(item) => { return present(item) },
                    none => { self.inner = none }
                },
                none => {}
            }
            match take self.outer.next_back() {
                present(item) => { self.inner = present(self.f(item)) },
                none => { return none }
            }
        }
        none
    }
}

pub type Enumerated<I> { iter: I; index: usize }
extend<I: Iterator> Enumerated<I> implements Iterator {
    type Item = (usize, I.Item)
    mut fn next(): (usize, I.Item)? {
        match take self.iter.next() {
            present(item) => {
                let index = self.index
                self.index += 1usize
                present((index, item))
            },
            none => none
        }
    }
}

// Ends as soon as either side ends; the first side is polled first.
pub type Zipped<A, B> { first: A; second: B }
extend<A: Iterator, B: Iterator> Zipped<A, B> implements Iterator {
    type Item = (A.Item, B.Item)
    mut fn next(): (A.Item, B.Item)? {
        match take self.first.next() {
            present(left) => match take self.second.next() {
                present(right) => present((left, right)),
                none => none
            },
            none => none
        }
    }
}

// `second` is dropped (set to none) once exhausted; `first_live` marks the front half.
pub type Chained<A, B> { first: A; second: B?; first_live: bool }
extend<T, A: Iterator<Item = T>, B: Iterator<Item = T>> Chained<A, B> implements Iterator {
    type Item = T
    mut fn next(): T? {
        if self.first_live {
            match take self.first.next() {
                present(item) => { return present(item) },
                none => { self.first_live = false }
            }
        }
        match mut self.second {
            present(rest) => rest.next(),
            none => none
        }
    }
}
extend<T, A: Iterator<Item = T> + BidirectionalIterator, B: Iterator<Item = T> + BidirectionalIterator> Chained<A, B> implements BidirectionalIterator {
    mut fn next_back(): T? {
        match mut self.second {
            present(rest) => match rest.next_back() {
                present(item) => { return present(item) },
                none => { self.second = none }
            },
            none => {}
        }
        if self.first_live {
            match take self.first.next_back() {
                present(item) => present(item),
                none => { self.first_live = false; none }
            }
        } else {
            none
        }
    }
}

pub type Limited<I> { iter: I; remaining: usize }
extend<I: Iterator> Limited<I> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? {
        if self.remaining == 0usize { return none }
        self.remaining -= 1usize
        self.iter.next()
    }
}

pub type Skipped<I> { iter: I; pending: usize }
extend<I: Iterator> Skipped<I> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? {
        if self.pending > 0usize {
            let count = self.pending
            self.pending = 0usize
            return self.iter.nth(count)
        }
        self.iter.next()
    }
}

pub type TakenWhile<I, F> { iter: I; test: F; done: bool }
extend<I: Iterator, F: fn(read I.Item): bool> TakenWhile<I, F> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? {
        if self.done { return none }
        match take self.iter.next() {
            present(item) => {
                if self.test(read item) { return present(item) }
                self.done = true
                none
            },
            none => { self.done = true; none }
        }
    }
}

pub type SkippedWhile<I, F> { iter: I; test: F; started: bool }
extend<I: Iterator, F: fn(read I.Item): bool> SkippedWhile<I, F> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? {
        if self.started { return self.iter.next() }
        while true {
            match take self.iter.next() {
                present(item) => {
                    if !self.test(read item) {
                        self.started = true
                        return present(item)
                    }
                },
                none => { return none }
            }
        }
        none
    }
}

pub type Stepped<I> { iter: I; step: usize; first: bool }
extend<I: Iterator> Stepped<I> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? {
        if self.first {
            self.first = false
            return self.iter.next()
        }
        self.iter.nth(self.step - 1usize)
    }
}

pub type Inspected<I, F> { iter: I; f: F }
extend<I: Iterator, F: fn(read I.Item): Unit> Inspected<I, F> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? {
        match take self.iter.next() {
            present(item) => { self.f(read item); present(item) },
            none => none
        }
    }
}

// Once `next` returned none it keeps returning none without polling again.
pub type Fused<I> { iter: I; done: bool }
extend<I: Iterator> Fused<I> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? {
        if self.done { return none }
        match take self.iter.next() {
            present(item) => present(item),
            none => { self.done = true; none }
        }
    }
}
extend<I: Iterator + BidirectionalIterator> Fused<I> implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? {
        if self.done { return none }
        match take self.iter.next_back() {
            present(item) => present(item),
            none => { self.done = true; none }
        }
    }
}

pub type Cycled<I> { original: I; iter: I; yielded: bool; done: bool }
extend<I: Iterator + Clone> Cycled<I> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? {
        if self.done { return none }
        while true {
            match take self.iter.next() {
                present(item) => { self.yielded = true; return present(item) },
                none => {
                    if self.yielded {
                        self.iter = self.original.clone()
                        self.yielded = false
                    } else {
                        self.done = true
                        return none
                    }
                }
            }
        }
        none
    }
}

pub type Reversed<I> { iter: I }
extend<I: Iterator + BidirectionalIterator> Reversed<I> implements Iterator {
    type Item = I.(Iterator).Item
    mut fn next(): I.(Iterator).Item? { self.iter.next_back() }
}
extend<I: Iterator + BidirectionalIterator> Reversed<I> implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? { self.iter.next() }
}

// `slot` holds the lookahead once `peek` ran: present(none) means the end was seen.
pub type Peekable<I: Iterator> { iter: I; slot: (I.(Iterator).Item?)?; filled: bool }
extend<I: Iterator> Peekable<I> {
    pub mut fn peek(): (read I.Item from self)? {
        if !self.filled {
            self.slot = present(self.iter.next())
            self.filled = true
        }
        match self.slot {
            present(held) => match held { present(item) => present(read item), none => none },
            none => none
        }
    }
}
extend<I: Iterator> Peekable<I> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? {
        if self.filled {
            self.filled = false
            return match take self.slot.take_value() { present(held) => held, none => none }
        }
        self.iter.next()
    }
}
extend<I: Iterator + BidirectionalIterator> Peekable<I> implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? {
        if self.filled {
            match take self.iter.next_back() {
                present(item) => present(item),
                none => {
                    self.filled = false
                    match take self.slot.take_value() {
                        present(held) => held,
                        none => none
                    }
                }
            }
        } else {
            self.iter.next_back()
        }
    }
}

// Sources.
pub type Once<T> { value: T? }
extend<T> Once<T> implements Iterator {
    type Item = T
    mut fn next(): T? { self.value.take_value() }
}
pub fn once<T>(value: take T): Once<T> { Once(present(value)) }

pub type Empty<T> { marker: Phantom<T> }
extend<T> Empty<T> implements Iterator {
    type Item = T
    mut fn next(): T? { none }
}
pub fn empty<T>(): Empty<T> { Empty(Phantom<T>()) }

// Calls `f` for every item; `f` returning none ends the iteration.
pub type FromFn<T, F> { f: F; item: Phantom<T> }
extend<T, F: fn(): T?> FromFn<T, F> implements Iterator {
    type Item = T
    mut fn next(): T? { self.f() }
}
pub fn from_fn<T, F: fn(): T?>(f: take F): FromFn<T, F> { FromFn(f, Phantom<T>()) }

// Endless iterator calling `f` for every item.
pub type RepeatWith<T, F> { f: F; item: Phantom<T> }
extend<T, F: fn(): T> RepeatWith<T, F> implements Iterator {
    type Item = T
    mut fn next(): T? { present(self.f()) }
}
pub fn repeat_with<T, F: fn(): T>(f: take F): RepeatWith<T, F> { RepeatWith(f, Phantom<T>()) }

// Stepping between neighbouring scalar values used by the range iterators.
// Absence marks a scalar type's endpoint.
pub interface Step: Sized + Copy + Ord {
    fn successor(): Self?;
    fn predecessor(): Self?;
}

// The unbounded range stops after yielding the scalar maximum.
pub type RangeFrom<T> { start: T; done: bool }
extend<T: Step> RangeFrom<T> implements Clone {
    fn clone(): RangeFrom<T> { RangeFrom(self.start, self.done) }
}
extend<T: Step> RangeFrom<T> implements Iterator {
    type Item = T
    mut fn next(): T? {
        if self.done { return none }
        let value = self.start
        match value.successor() {
            present(next) => { self.start = next },
            none => { self.done = true }
        }
        present(value)
    }
}
pub fn range_from<T: Step>(start: T): RangeFrom<T> { RangeFrom(start, false) }

// The half-open range `[start, end)`.
pub type Range<T> { start: T; end: T }
extend<T: Step> Range<T> implements Clone {
    fn clone(): Range<T> { Range(self.start, self.end) }
}
extend<T: Step> Range<T> implements Iterator {
    type Item = T
    mut fn next(): T? {
        if self.start < self.end {
            let value = self.start
            match value.successor() {
                present(next) => { self.start = next },
                none => { self.start = self.end }
            }
            return present(value)
        }
        none
    }
}
extend<T: Step> Range<T> implements BidirectionalIterator {
    mut fn next_back(): T? {
        if self.start < self.end {
            match self.end.predecessor() {
                present(previous) => { self.end = previous },
                none => { self.start = self.end }
            }
            return present(self.end)
        }
        none
    }
}
pub fn range<T: Step>(start: T, end: T): Range<T> { Range(start, end) }

pub type RangeTo<T> { end: T }
pub fn range_to<T>(end: take T): RangeTo<T> { RangeTo(end) }

pub type RangeFull {}
pub fn range_full(): RangeFull { RangeFull() }

pub type RangeToInclusive<T> { end: T }
pub fn range_to_inclusive<T>(end: take T): RangeToInclusive<T> {
    RangeToInclusive(end)
}

// The closed range `[start, end]`; `done` avoids stepping past the type's bounds.
pub type RangeInclusive<T> { start: T; end: T; done: bool }
extend<T: Step> RangeInclusive<T> implements Clone {
    fn clone(): RangeInclusive<T> { RangeInclusive(self.start, self.end, self.done) }
}
extend<T: Step> RangeInclusive<T> implements Iterator {
    type Item = T
    mut fn next(): T? {
        if self.done || self.start > self.end { return none }
        let value = self.start
        if value == self.end {
            self.done = true
        } else {
            match value.successor() {
                present(next) => { self.start = next },
                none => { self.done = true }
            }
        }
        present(value)
    }
}
extend<T: Step> RangeInclusive<T> implements BidirectionalIterator {
    mut fn next_back(): T? {
        if self.done || self.start > self.end { return none }
        let value = self.end
        if value == self.start {
            self.done = true
        } else {
            match value.predecessor() {
                present(previous) => { self.end = previous },
                none => { self.done = true }
            }
        }
        present(value)
    }
}
pub fn range_inclusive<T: Step>(start: T, end: T): RangeInclusive<T> { RangeInclusive(start, end, false) }

// Folding capabilities: `zero`/`one` are the identities of `plus`/`times`.
pub interface Sum: Sized {
    static fn zero(): Self;
    fn plus(other: take Self): Self;
}
pub interface Product: Sized {
    static fn one(): Self;
    fn times(other: take Self): Self;
}
pub fn sum<I: Iterator>(items: take I): I.Item where I.Item: Sum {
    var source = items
    var total = I.Item.(Sum).zero()
    while true {
        match take source.next() { present(item) => { total = total.plus(item) }, none => { break } }
    }
    total
}
pub fn product<I: Iterator>(items: take I): I.Item where I.Item: Product {
    var source = items
    var total = I.Item.(Product).one()
    while true {
        match take source.next() { present(item) => { total = total.times(item) }, none => { break } }
    }
    total
}
pub fn max<I: Iterator>(items: take I): I.Item? where I.Item: Ord {
    var source = items
    var best = source.next()
    while true {
        match take source.next() {
            present(item) => {
                match take best {
                    present(current) => { best = present(super.cmp.max(current, item)) },
                    none => { best = present(item) }
                }
            },
            none => { break }
        }
    }
    best
}
pub fn min<I: Iterator>(items: take I): I.Item? where I.Item: Ord {
    var source = items
    var best = source.next()
    while true {
        match take source.next() {
            present(item) => {
                match take best {
                    present(current) => { best = present(super.cmp.min(current, item)) },
                    none => { best = present(item) }
                }
            },
            none => { break }
        }
    }
    best
}

extend i8 implements Step {
    fn successor(): i8? { self.checked_add(1i8) }
    fn predecessor(): i8? { self.checked_sub(1i8) }
}
extend i8 implements Sum {
    static fn zero(): i8 { 0i8 }
    fn plus(other: take i8): i8 { self + other }
}
extend i8 implements Product {
    static fn one(): i8 { 1i8 }
    fn times(other: take i8): i8 { self * other }
}

extend i16 implements Step {
    fn successor(): i16? { self.checked_add(1i16) }
    fn predecessor(): i16? { self.checked_sub(1i16) }
}
extend i16 implements Sum {
    static fn zero(): i16 { 0i16 }
    fn plus(other: take i16): i16 { self + other }
}
extend i16 implements Product {
    static fn one(): i16 { 1i16 }
    fn times(other: take i16): i16 { self * other }
}

extend i32 implements Step {
    fn successor(): i32? { self.checked_add(1i32) }
    fn predecessor(): i32? { self.checked_sub(1i32) }
}
extend i32 implements Sum {
    static fn zero(): i32 { 0i32 }
    fn plus(other: take i32): i32 { self + other }
}
extend i32 implements Product {
    static fn one(): i32 { 1i32 }
    fn times(other: take i32): i32 { self * other }
}

extend i64 implements Step {
    fn successor(): i64? { self.checked_add(1i64) }
    fn predecessor(): i64? { self.checked_sub(1i64) }
}
extend i64 implements Sum {
    static fn zero(): i64 { 0i64 }
    fn plus(other: take i64): i64 { self + other }
}
extend i64 implements Product {
    static fn one(): i64 { 1i64 }
    fn times(other: take i64): i64 { self * other }
}

extend i128 implements Step {
    fn successor(): i128? { self.checked_add(1i128) }
    fn predecessor(): i128? { self.checked_sub(1i128) }
}

extend isize implements Step {
    fn successor(): isize? { self.checked_add(1isize) }
    fn predecessor(): isize? { self.checked_sub(1isize) }
}
extend isize implements Sum {
    static fn zero(): isize { 0isize }
    fn plus(other: take isize): isize { self + other }
}
extend isize implements Product {
    static fn one(): isize { 1isize }
    fn times(other: take isize): isize { self * other }
}

extend u8 implements Step {
    fn successor(): u8? { self.checked_add(1u8) }
    fn predecessor(): u8? { self.checked_sub(1u8) }
}
extend u8 implements Sum {
    static fn zero(): u8 { 0u8 }
    fn plus(other: take u8): u8 { self + other }
}
extend u8 implements Product {
    static fn one(): u8 { 1u8 }
    fn times(other: take u8): u8 { self * other }
}

extend u16 implements Step {
    fn successor(): u16? { self.checked_add(1u16) }
    fn predecessor(): u16? { self.checked_sub(1u16) }
}
extend u16 implements Sum {
    static fn zero(): u16 { 0u16 }
    fn plus(other: take u16): u16 { self + other }
}
extend u16 implements Product {
    static fn one(): u16 { 1u16 }
    fn times(other: take u16): u16 { self * other }
}

extend u32 implements Step {
    fn successor(): u32? { self.checked_add(1u32) }
    fn predecessor(): u32? { self.checked_sub(1u32) }
}
extend u32 implements Sum {
    static fn zero(): u32 { 0u32 }
    fn plus(other: take u32): u32 { self + other }
}
extend u32 implements Product {
    static fn one(): u32 { 1u32 }
    fn times(other: take u32): u32 { self * other }
}

extend u64 implements Step {
    fn successor(): u64? { self.checked_add(1u64) }
    fn predecessor(): u64? { self.checked_sub(1u64) }
}
extend u64 implements Sum {
    static fn zero(): u64 { 0u64 }
    fn plus(other: take u64): u64 { self + other }
}
extend u64 implements Product {
    static fn one(): u64 { 1u64 }
    fn times(other: take u64): u64 { self * other }
}

extend u128 implements Step {
    fn successor(): u128? { self.checked_add(1u128) }
    fn predecessor(): u128? { self.checked_sub(1u128) }
}

extend usize implements Step {
    fn successor(): usize? { self.checked_add(1usize) }
    fn predecessor(): usize? { self.checked_sub(1usize) }
}

extend char implements Step {
    fn successor(): char? {
        let value = self as u32
        let next = if value == 0xd7ffu32 { 0xe000u32 } else { value + 1u32 }
        super.char.from_u32(next)
    }
    fn predecessor(): char? {
        let value = self as u32
        if value == 0u32 { return none }
        let previous = if value == 0xe000u32 { 0xd7ffu32 } else { value - 1u32 }
        super.char.from_u32(previous)
    }
}
extend usize implements Sum {
    static fn zero(): usize { 0usize }
    fn plus(other: take usize): usize { self + other }
}
extend usize implements Product {
    static fn one(): usize { 1usize }
    fn times(other: take usize): usize { self * other }
}
