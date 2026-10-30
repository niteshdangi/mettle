// Iteration. The compiler recognizes `Iterator`, `IntoIterator`, `Iterable`
// and `IterableMut` by canonical path for `for` loops. Adapters are lazy: they
// pull from the wrapped iterator only when `next` is called, and consuming
// methods stop at the first decisive item.
import super::cmp::Ord;
import super::option;
import super::cmp::Ordering;

pub interface Iterator: Sized {
    type Item;
    mut fn next(): Self::Item?;

    // Bounds on the remaining length: `(lower, upper)`; `upper` is none when unknown.
    fn size_hint(): (usize, usize?) { (0usize, none) }

    mut fn count(): usize {
        var total = 0usize
        while true {
            match take self.next() { present(item) => { total += 1usize }, none => { break } }
        }
        total
    }
    take fn last(): Self::Item? {
        var remaining = self
        var result: Self::Item? = none
        while true {
            match take remaining.next() { present(item) => { result = present(item) }, none => { break } }
        }
        result
    }
    // Consumes `n` items first; the item after them is returned.
    mut fn nth(n: usize): Self::Item? {
        var skipped = 0usize
        while skipped < n {
            match take self.next() { present(item) => { skipped += 1usize }, none => { return none } }
        }
        self.next()
    }
    mut fn fold<B, F: fn(take B, take Self::Item): B>(start: take B, f: take F): B {
        var accumulator = start
        while true {
            match take self.next() {
                present(item) => { accumulator = f(take accumulator, item) },
                none => { break }
            }
        }
        accumulator
    }
    mut fn for_each<F: fn(take Self::Item): Unit>(f: take F): Unit {
        while true {
            match take self.next() { present(item) => { f(item) }, none => { break } }
        }
    }
    // Stops at the first item for which `test` holds.
    mut fn any<F: fn(take Self::Item): bool>(test: take F): bool {
        while true {
            match take self.next() {
                present(item) => { if test(item) { return true } },
                none => { break }
            }
        }
        false
    }
    // Stops at the first item for which `test` fails.
    mut fn all<F: fn(take Self::Item): bool>(test: take F): bool {
        while true {
            match take self.next() {
                present(item) => { if !test(item) { return false } },
                none => { break }
            }
        }
        true
    }
    mut fn find<F: fn(read Self::Item): bool>(test: take F): Self::Item? {
        while true {
            match take self.next() {
                present(item) => { if test(read item) { return present(item) } },
                none => { break }
            }
        }
        none
    }
    mut fn position<F: fn(take Self::Item): bool>(test: take F): usize? {
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
    mut fn find_map<B, F: fn(take Self::Item): B?>(f: take F): B? {
        while true {
            match take self.next() {
                present(item) => { match take f(item) { present(found) => { return present(found) }, none => {} } },
                none => { break }
            }
        }
        none
    }

    take fn map<B, F: fn(take Self::Item): B>(f: take F): Map<B, Self, F> { Map(self, f, Phantom::<B>()) }
    take fn filter<F: fn(read Self::Item): bool>(test: take F): Filter<Self, F> { Filter(self, test) }
    take fn filter_map<B, F: fn(take Self::Item): B?>(f: take F): FilterMap<B, Self, F> {
        FilterMap(self, f, Phantom::<B>())
    }
    take fn enumerate(): Enumerate<Self> { Enumerate(self, 0usize) }
    take fn zip<U: Iterator>(other: take U): Zip<Self, U> { Zip(self, other) }
    take fn chain<U: Iterator>(other: take U): Chain<Self, U> { Chain(self, present(other), true) }
    take fn take_n(n: usize): TakeN<Self> { TakeN(self, n) }
    take fn skip(n: usize): Skip<Self> { Skip(self, n) }
    take fn take_while<F: fn(read Self::Item): bool>(test: take F): TakeWhile<Self, F> { TakeWhile(self, test, false) }
    take fn skip_while<F: fn(read Self::Item): bool>(test: take F): SkipWhile<Self, F> { SkipWhile(self, test, false) }
    // `step` must be nonzero; the first item is always produced.
    take fn step_by(step: usize): StepBy<Self> { StepBy(self, step, true) }
    take fn peekable(): Peekable<Self> { Peekable(self, none, false) }
    take fn inspect<F: fn(read Self::Item): Unit>(f: take F): Inspect<Self, F> { Inspect(self, f) }
    take fn fuse(): Fuse<Self> { Fuse(self, false) }
    take fn collect<C: FromIterator<Self::Item>>(): C { <C implements FromIterator<Self::Item>>::from_iter(self) }
}

// Collections that can be built from, or grown by, a sequence of owned items.
pub interface FromIterator<T>: Sized {
    static fn from_iter<I: IntoIterator<Item = T>>(items: take I): Self;
}
pub interface Extend<T> {
    mut fn extend<I: IntoIterator<Item = T>>(items: take I): Unit;
}
// `let v: Vec<i32> = collect(items)`.
pub fn collect<T, I: IntoIterator<Item = T>, C: FromIterator<T>>(items: take I): C {
    <C implements FromIterator<T>>::from_iter(items)
}

// Iterators that can also yield from the back.
pub interface DoubleEndedIterator: Iterator {
    mut fn next_back(): <Self implements Iterator>::Item?;
    take fn rev(): Rev<Self> { Rev(self) }
}

pub interface IntoIterator: Sized {
    type Item;
    type IntoIter: Iterator<Item = Self::Item>;
    fn into_iter(receiver self: take Self): Self::IntoIter;
}

// Borrowing iteration; the iterator is tied to the borrow of the receiver
// through the family region `r`, so `for x in read c` yields `read Item from c`,
// `for x in mut c` yields `mut Item from c`, and generic code can call `next`
// on `c.iter()`.
pub interface Iterable {
    type Item;
    type Iter<region r>: Iterator<Item = read Self::Item from r>;
    fn iter<region r>(receiver self: read Self from r): Self::Iter<region r>;
}

pub interface IterableMut {
    type Item;
    type IterMut<region r>: Iterator<Item = mut Self::Item from r>;
    fn iter_mut<region r>(receiver self: mut Self from r): Self::IterMut<region r>;
}

// Every iterator is trivially its own IntoIterator.
impl<I: Iterator> I implements IntoIterator {
    type Item = I::Item
    type IntoIter = I
    fn into_iter(receiver self: take Self): I { self }
}

pub type Phantom<T> {}

pub type Map<B, I, F> { iter: I; f: F; result: Phantom<B> }
impl<B, I: Iterator, F: fn(take I::Item): B> Map<B, I, F> implements Iterator {
    type Item = B
    mut fn next(): B? {
        match take self.iter.next() { present(item) => present(self.f(item)), none => none }
    }
}
impl<B, I: Iterator + DoubleEndedIterator, F: fn(take <I implements Iterator>::Item): B> Map<B, I, F> implements DoubleEndedIterator {
    mut fn next_back(): B? {
        match take self.iter.next_back() { present(item) => present(self.f(item)), none => none }
    }
}

pub type Filter<I, F> { iter: I; test: F }
impl<I: Iterator, F: fn(read I::Item): bool> Filter<I, F> implements Iterator {
    type Item = I::Item
    mut fn next(): I::Item? {
        while true {
            match take self.iter.next() {
                present(item) => { if self.test(read item) { return present(item) } },
                none => { break }
            }
        }
        none
    }
}
impl<I: Iterator + DoubleEndedIterator, F: fn(read <I implements Iterator>::Item): bool> Filter<I, F> implements DoubleEndedIterator {
    mut fn next_back(): <I implements Iterator>::Item? {
        while true {
            match take self.iter.next_back() {
                present(item) => { if self.test(read item) { return present(item) } },
                none => { break }
            }
        }
        none
    }
}

pub type FilterMap<B, I, F> { iter: I; f: F; result: Phantom<B> }
impl<B, I: Iterator, F: fn(take I::Item): B?> FilterMap<B, I, F> implements Iterator {
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

pub type Enumerate<I> { iter: I; index: usize }
impl<I: Iterator> Enumerate<I> implements Iterator {
    type Item = (usize, I::Item)
    mut fn next(): (usize, I::Item)? {
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
pub type Zip<A, B> { first: A; second: B }
impl<A: Iterator, B: Iterator> Zip<A, B> implements Iterator {
    type Item = (A::Item, B::Item)
    mut fn next(): (A::Item, B::Item)? {
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
pub type Chain<A, B> { first: A; second: B?; first_live: bool }
impl<T, A: Iterator<Item = T>, B: Iterator<Item = T>> Chain<A, B> implements Iterator {
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

pub type TakeN<I> { iter: I; remaining: usize }
impl<I: Iterator> TakeN<I> implements Iterator {
    type Item = I::Item
    mut fn next(): I::Item? {
        if self.remaining == 0usize { return none }
        self.remaining -= 1usize
        self.iter.next()
    }
}

pub type Skip<I> { iter: I; pending: usize }
impl<I: Iterator> Skip<I> implements Iterator {
    type Item = I::Item
    mut fn next(): I::Item? {
        if self.pending > 0usize {
            let count = self.pending
            self.pending = 0usize
            return self.iter.nth(count)
        }
        self.iter.next()
    }
}

pub type TakeWhile<I, F> { iter: I; test: F; done: bool }
impl<I: Iterator, F: fn(read I::Item): bool> TakeWhile<I, F> implements Iterator {
    type Item = I::Item
    mut fn next(): I::Item? {
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

pub type SkipWhile<I, F> { iter: I; test: F; started: bool }
impl<I: Iterator, F: fn(read I::Item): bool> SkipWhile<I, F> implements Iterator {
    type Item = I::Item
    mut fn next(): I::Item? {
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

pub type StepBy<I> { iter: I; step: usize; first: bool }
impl<I: Iterator> StepBy<I> implements Iterator {
    type Item = I::Item
    mut fn next(): I::Item? {
        if self.first {
            self.first = false
            return self.iter.next()
        }
        self.iter.nth(self.step - 1usize)
    }
}

pub type Inspect<I, F> { iter: I; f: F }
impl<I: Iterator, F: fn(read I::Item): Unit> Inspect<I, F> implements Iterator {
    type Item = I::Item
    mut fn next(): I::Item? {
        match take self.iter.next() {
            present(item) => { self.f(read item); present(item) },
            none => none
        }
    }
}

// Once `next` returned none it keeps returning none without polling again.
pub type Fuse<I> { iter: I; done: bool }
impl<I: Iterator> Fuse<I> implements Iterator {
    type Item = I::Item
    mut fn next(): I::Item? {
        if self.done { return none }
        match take self.iter.next() {
            present(item) => present(item),
            none => { self.done = true; none }
        }
    }
}

pub type Rev<I> { iter: I }
impl<I: Iterator + DoubleEndedIterator> Rev<I> implements Iterator {
    type Item = <I implements Iterator>::Item
    mut fn next(): <I implements Iterator>::Item? { self.iter.next_back() }
}
impl<I: Iterator + DoubleEndedIterator> Rev<I> implements DoubleEndedIterator {
    mut fn next_back(): <I implements Iterator>::Item? { self.iter.next() }
}

// `slot` holds the lookahead once `peek` ran: present(none) means the end was seen.
pub type Peekable<I: Iterator> { iter: I; slot: (<I implements Iterator>::Item?)?; filled: bool }
impl<I: Iterator> Peekable<I> {
    pub mut fn peek(): (read I::Item from self)? {
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
impl<I: Iterator> Peekable<I> implements Iterator {
    type Item = I::Item
    mut fn next(): I::Item? {
        if self.filled {
            self.filled = false
            return match take self.slot.take_value() { present(held) => held, none => none }
        }
        self.iter.next()
    }
}

// Sources.
pub type Once<T> { value: T? }
impl<T> Once<T> implements Iterator {
    type Item = T
    mut fn next(): T? { self.value.take_value() }
}
pub fn once<T>(value: take T): Once<T> { Once(present(value)) }

pub type Empty<T> { marker: Phantom<T> }
impl<T> Empty<T> implements Iterator {
    type Item = T
    mut fn next(): T? { none }
}
pub fn empty<T>(): Empty<T> { Empty(Phantom::<T>()) }

// Calls `f` for every item; `f` returning none ends the iteration.
pub type FromFn<T, F> { f: F; item: Phantom<T> }
impl<T, F: fn(): T?> FromFn<T, F> implements Iterator {
    type Item = T
    mut fn next(): T? { self.f() }
}
pub fn from_fn<T, F: fn(): T?>(f: take F): FromFn<T, F> { FromFn(f, Phantom::<T>()) }

// Endless iterator calling `f` for every item.
pub type RepeatWith<T, F> { f: F; item: Phantom<T> }
impl<T, F: fn(): T> RepeatWith<T, F> implements Iterator {
    type Item = T
    mut fn next(): T? { present(self.f()) }
}
pub fn repeat_with<T, F: fn(): T>(f: take F): RepeatWith<T, F> { RepeatWith(f, Phantom::<T>()) }

// Stepping between neighbouring integers, used by the range iterators.
pub interface Step: Sized + Copy + Ord {
    fn successor(): Self;
    fn predecessor(): Self;
}

// The half-open range `[start, end)`.
pub type Range<T> { start: T; end: T }
impl<T: Step> Range<T> implements Iterator {
    type Item = T
    mut fn next(): T? {
        if self.start < self.end {
            let value = self.start
            self.start = value.successor()
            return present(value)
        }
        none
    }
}
impl<T: Step> Range<T> implements DoubleEndedIterator {
    mut fn next_back(): T? {
        if self.start < self.end {
            self.end = self.end.predecessor()
            return present(self.end)
        }
        none
    }
}
pub fn range<T: Step>(start: T, end: T): Range<T> { Range(start, end) }

// The closed range `[start, end]`; `done` avoids stepping past the type's bounds.
pub type RangeInclusive<T> { start: T; end: T; done: bool }
impl<T: Step> RangeInclusive<T> implements Iterator {
    type Item = T
    mut fn next(): T? {
        if self.done || self.start > self.end { return none }
        let value = self.start
        if value == self.end { self.done = true } else { self.start = value.successor() }
        present(value)
    }
}
impl<T: Step> RangeInclusive<T> implements DoubleEndedIterator {
    mut fn next_back(): T? {
        if self.done || self.start > self.end { return none }
        let value = self.end
        if value == self.start { self.done = true } else { self.end = value.predecessor() }
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
pub fn sum<I: Iterator>(items: take I): I::Item where I::Item: Sum {
    var source = items
    var total = <I::Item implements Sum>::zero()
    while true {
        match take source.next() { present(item) => { total = total.plus(item) }, none => { break } }
    }
    total
}
pub fn product<I: Iterator>(items: take I): I::Item where I::Item: Product {
    var source = items
    var total = <I::Item implements Product>::one()
    while true {
        match take source.next() { present(item) => { total = total.times(item) }, none => { break } }
    }
    total
}
pub fn max<I: Iterator>(items: take I): I::Item? where I::Item: Ord {
    var source = items
    var best = source.next()
    while true {
        match take source.next() {
            present(item) => {
                match take best {
                    present(current) => { best = present(super::cmp::max(current, item)) },
                    none => { best = present(item) }
                }
            },
            none => { break }
        }
    }
    best
}
pub fn min<I: Iterator>(items: take I): I::Item? where I::Item: Ord {
    var source = items
    var best = source.next()
    while true {
        match take source.next() {
            present(item) => {
                match take best {
                    present(current) => { best = present(super::cmp::min(current, item)) },
                    none => { best = present(item) }
                }
            },
            none => { break }
        }
    }
    best
}

impl i8 implements Step {
    fn successor(): i8 { self + 1i8 }
    fn predecessor(): i8 { self - 1i8 }
}
impl i8 implements Sum {
    static fn zero(): i8 { 0i8 }
    fn plus(other: take i8): i8 { self + other }
}
impl i8 implements Product {
    static fn one(): i8 { 1i8 }
    fn times(other: take i8): i8 { self * other }
}

impl i16 implements Step {
    fn successor(): i16 { self + 1i16 }
    fn predecessor(): i16 { self - 1i16 }
}
impl i16 implements Sum {
    static fn zero(): i16 { 0i16 }
    fn plus(other: take i16): i16 { self + other }
}
impl i16 implements Product {
    static fn one(): i16 { 1i16 }
    fn times(other: take i16): i16 { self * other }
}

impl i32 implements Step {
    fn successor(): i32 { self + 1i32 }
    fn predecessor(): i32 { self - 1i32 }
}
impl i32 implements Sum {
    static fn zero(): i32 { 0i32 }
    fn plus(other: take i32): i32 { self + other }
}
impl i32 implements Product {
    static fn one(): i32 { 1i32 }
    fn times(other: take i32): i32 { self * other }
}

impl i64 implements Step {
    fn successor(): i64 { self + 1i64 }
    fn predecessor(): i64 { self - 1i64 }
}
impl i64 implements Sum {
    static fn zero(): i64 { 0i64 }
    fn plus(other: take i64): i64 { self + other }
}
impl i64 implements Product {
    static fn one(): i64 { 1i64 }
    fn times(other: take i64): i64 { self * other }
}

impl isize implements Step {
    fn successor(): isize { self + 1isize }
    fn predecessor(): isize { self - 1isize }
}
impl isize implements Sum {
    static fn zero(): isize { 0isize }
    fn plus(other: take isize): isize { self + other }
}
impl isize implements Product {
    static fn one(): isize { 1isize }
    fn times(other: take isize): isize { self * other }
}

impl u8 implements Step {
    fn successor(): u8 { self + 1u8 }
    fn predecessor(): u8 { self - 1u8 }
}
impl u8 implements Sum {
    static fn zero(): u8 { 0u8 }
    fn plus(other: take u8): u8 { self + other }
}
impl u8 implements Product {
    static fn one(): u8 { 1u8 }
    fn times(other: take u8): u8 { self * other }
}

impl u16 implements Step {
    fn successor(): u16 { self + 1u16 }
    fn predecessor(): u16 { self - 1u16 }
}
impl u16 implements Sum {
    static fn zero(): u16 { 0u16 }
    fn plus(other: take u16): u16 { self + other }
}
impl u16 implements Product {
    static fn one(): u16 { 1u16 }
    fn times(other: take u16): u16 { self * other }
}

impl u32 implements Step {
    fn successor(): u32 { self + 1u32 }
    fn predecessor(): u32 { self - 1u32 }
}
impl u32 implements Sum {
    static fn zero(): u32 { 0u32 }
    fn plus(other: take u32): u32 { self + other }
}
impl u32 implements Product {
    static fn one(): u32 { 1u32 }
    fn times(other: take u32): u32 { self * other }
}

impl u64 implements Step {
    fn successor(): u64 { self + 1u64 }
    fn predecessor(): u64 { self - 1u64 }
}
impl u64 implements Sum {
    static fn zero(): u64 { 0u64 }
    fn plus(other: take u64): u64 { self + other }
}
impl u64 implements Product {
    static fn one(): u64 { 1u64 }
    fn times(other: take u64): u64 { self * other }
}

impl usize implements Step {
    fn successor(): usize { self + 1usize }
    fn predecessor(): usize { self - 1usize }
}
impl usize implements Sum {
    static fn zero(): usize { 0usize }
    fn plus(other: take usize): usize { self + other }
}
impl usize implements Product {
    static fn one(): usize { 1usize }
    fn times(other: take usize): usize { self * other }
}
