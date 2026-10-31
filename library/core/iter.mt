// Iteration. The compiler recognizes `Iterator`, `OwnedIterable`, `Iterable`
// and `MutableIterable` by canonical path for `for` loops. Adapters are lazy: they
// pull from the wrapped iterator only when `next` is called, and consuming
// methods stop at the first decisive item.
import super.cmp.Ord
import super.cmp.PartialEq
import super.cmp.PartialOrd
import super.default.Default
import super.option
import super.cmp.Ordering
import super.clone.Clone
import super.fmt

// A mutable borrow of an iterator. Adapters move this borrow, so
// `by_ref().take_n(n)` consumes only `n` items of the borrowed iterator.
pub type ByRef<region r, I> { iter: mut I from r }

pub interface Iterator: Sized {
    type Item;
    mut fn next(): Self.Item?;

    // Bounds on the remaining length: `(lower, upper)`; `upper` is none when unknown.
    fn size_hint(): (usize, usize?) { (0usize, none) }
    fn by_ref<region r>(receiver self: mut Self from r): ByRef<region r, Self> {
        ByRef(mut self)
    }

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
    mut fn fold<B, F: mut fn(take B, take Self.Item): B>(start: take B, f: mut F): B {
        var accumulator = start
        while true {
            match take self.next() {
                present(item) => { accumulator = f(take accumulator, item) },
                none => { break }
            }
        }
        accumulator
    }
    mut fn for_each<F: mut fn(take Self.Item): Unit>(f: mut F): Unit {
        while true {
            match take self.next() { present(item) => { f(item) }, none => { break } }
        }
    }
    mut fn try_fold<B, E, F: mut fn(take B, take Self.Item): B throws E>(
        start: take B,
        f: mut F
    ): (B throws E) {
        var accumulator = start
        while true {
            match take self.next() {
                present(item) => match take capture f(take accumulator, item) {
                    success(value) => { accumulator = value },
                    failure(error) => { return failure(error) }
                },
                none => { break }
            }
        }
        success(accumulator)
    }
    mut fn try_for_each<E, F: mut fn(take Self.Item): Unit throws E>(f: mut F): (Unit throws E) {
        while true {
            match take self.next() {
                present(item) => match take capture f(item) {
                    success(_) => {},
                    failure(error) => { return failure(error) }
                },
                none => { break }
            }
        }
        success(())
    }
    // Stops at the first item for which `test` holds.
    mut fn any<F: mut fn(take Self.Item): bool>(test: mut F): bool {
        while true {
            match take self.next() {
                present(item) => { if test(item) { return true } },
                none => { break }
            }
        }
        false
    }
    // Stops at the first item for which `test` fails.
    mut fn all<F: mut fn(take Self.Item): bool>(test: mut F): bool {
        while true {
            match take self.next() {
                present(item) => { if !test(item) { return false } },
                none => { break }
            }
        }
        true
    }
    mut fn find<F: mut fn(read Self.Item): bool>(test: mut F): Self.Item? {
        while true {
            match take self.next() {
                present(item) => { if test(read item) { return present(item) } },
                none => { break }
            }
        }
        none
    }
    mut fn position<F: mut fn(take Self.Item): bool>(test: mut F): usize? {
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
    mut fn find_map<B, F: mut fn(take Self.Item): B?>(f: mut F): B? {
        while true {
            match take self.next() {
                present(item) => { match take f(item) { present(found) => { return present(found) }, none => {} } },
                none => { break }
            }
        }
        none
    }
    mut fn min_by<F: mut fn(read Self.Item, read Self.Item): Ordering>(compare: mut F): Self.Item? {
        var best = self.next()
        while true {
            match take self.next() {
                present(item) => match take best {
                    present(current) => {
                        if compare(read item, read current).is_lt() {
                            best = present(item)
                        } else {
                            best = present(current)
                        }
                    },
                    none => { best = present(item) }
                },
                none => { break }
            }
        }
        best
    }
    mut fn max_by<F: mut fn(read Self.Item, read Self.Item): Ordering>(compare: mut F): Self.Item? {
        var best = self.next()
        while true {
            match take self.next() {
                present(item) => match take best {
                    present(current) => {
                        if compare(read item, read current).is_gt() {
                            best = present(item)
                        } else {
                            best = present(current)
                        }
                    },
                    none => { best = present(item) }
                },
                none => { break }
            }
        }
        best
    }
    mut fn min_by_key<K: Ord, F: mut fn(read Self.Item): K>(key: mut F): Self.Item? {
        var best: (Self.Item, K)? = match take self.next() {
            present(item) => {
                let item_key = key(read item)
                present((item, item_key))
            },
            none => none
        }
        while true {
            match take self.next() {
                present(item) => {
                    let item_key = key(read item)
                    match take best {
                        present((current, current_key)) => {
                            if item_key.cmp(read current_key).is_lt() {
                                best = present((item, item_key))
                            } else {
                                best = present((current, current_key))
                            }
                        },
                        none => { best = present((item, item_key)) }
                    }
                },
                none => { break }
            }
        }
        match take best { present((item, _)) => present(item), none => none }
    }
    mut fn max_by_key<K: Ord, F: mut fn(read Self.Item): K>(key: mut F): Self.Item? {
        var best: (Self.Item, K)? = match take self.next() {
            present(item) => {
                let item_key = key(read item)
                present((item, item_key))
            },
            none => none
        }
        while true {
            match take self.next() {
                present(item) => {
                    let item_key = key(read item)
                    match take best {
                        present((current, current_key)) => {
                            if item_key.cmp(read current_key).is_gt() {
                                best = present((item, item_key))
                            } else {
                                best = present((current, current_key))
                            }
                        },
                        none => { best = present((item, item_key)) }
                    }
                },
                none => { break }
            }
        }
        match take best { present((item, _)) => present(item), none => none }
    }
    mut fn reduce<F: mut fn(take Self.Item, take Self.Item): Self.Item>(f: mut F): Self.Item? {
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

    take fn map<B, F: mut fn(take Self.Item): B>(f: take F): Mapped<B, Self, F> { Mapped(self, f, Phantom<B>()) }
    take fn filter<F: mut fn(read Self.Item): bool>(test: take F): Filtered<Self, F> { Filtered(self, test) }
    take fn filter_map<B, F: mut fn(take Self.Item): B?>(f: take F): FilterMapped<B, Self, F> {
        FilterMapped(self, f, Phantom<B>())
    }
    take fn map_while<B, F: mut fn(take Self.Item): B?>(f: take F): MappedWhile<B, Self, F> {
        MappedWhile(self, f, Phantom<B>())
    }
    take fn flat_map<U: Iterator, F: mut fn(take Self.Item): U>(f: take F): FlatMapped<Self, U, F> {
        FlatMapped(self, none, f)
    }
    take fn flatten(): Flatten<Self.Item, Self> where Self.Item: Iterator {
        Flatten(self, none, none, false)
    }
    take fn cloned<region r, T: Clone>(): Cloned<region r, T, Self> where Self.Item = read T from r {
        Cloned(self, Phantom<T>())
    }
    take fn copied<region r, T: Copy>(): Copied<region r, T, Self> where Self.Item = read T from r {
        Copied(self, Phantom<T>())
    }
    take fn scan<B, S, F: mut fn(mut S, take Self.Item): B?>(
        state: take S,
        f: take F
    ): Scanned<B, Self, S, F> {
        Scanned(self, state, f, Phantom<B>())
    }
    take fn enumerate(): Enumerated<Self> { Enumerated(self, 0usize) }
    take fn zip<U: Iterator>(other: take U): Zipped<Self, U> { Zipped(self, other) }
    take fn chain<U: Iterator>(other: take U): Chained<Self, U> { Chained(self, present(other), true) }
    take fn take_n(n: usize): Limited<Self> { Limited(self, n) }
    take fn skip(n: usize): Skipped<Self> { Skipped(self, n) }
    take fn take_while<F: mut fn(read Self.Item): bool>(test: take F): TakenWhile<Self, F> { TakenWhile(self, test, false) }
    take fn skip_while<F: mut fn(read Self.Item): bool>(test: take F): SkippedWhile<Self, F> { SkippedWhile(self, test, false) }
    // The first item is produced before every subsequent `step`th item.
    take fn step_by(step: usize): Stepped<Self> {
        if step == 0usize { super.panic.panic("step_by step must be nonzero") }
        Stepped(self, step, true)
    }
    take fn peekable(): Peekable<Self> { Peekable(self, none, false) }
    mut fn cmp<I: Iterator<Item = Self.Item>>(other: take I): Ordering where Self.Item: Ord {
        var rest = other
        while true {
            match take self.next() {
                present(left) => match take rest.next() {
                    present(right) => {
                        let order = left.cmp(read right)
                        if !order.is_eq() { return order }
                    },
                    none => { return Ordering.Greater }
                },
                none => match take rest.next() {
                    present(right) => { return Ordering.Less },
                    none => { return Ordering.Equal }
                }
            }
        }
        Ordering.Equal
    }
    mut fn partial_cmp<I: Iterator<Item = Self.Item>>(other: take I): Ordering? where Self.Item: PartialOrd {
        var rest = other
        while true {
            match take self.next() {
                present(left) => match take rest.next() {
                    present(right) => match left.partial_cmp(read right) {
                        present(order) => { if !order.is_eq() { return present(order) } },
                        none => { return none }
                    },
                    none => { return present(Ordering.Greater) }
                },
                none => match take rest.next() {
                    present(right) => { return present(Ordering.Less) },
                    none => { return present(Ordering.Equal) }
                }
            }
        }
        present(Ordering.Equal)
    }
    mut fn eq<I: Iterator<Item = Self.Item>>(other: take I): bool where Self.Item: PartialEq {
        var rest = other
        while true {
            match take self.next() {
                present(left) => match take rest.next() {
                    present(right) => { if left != right { return false } },
                    none => { return false }
                },
                none => match take rest.next() {
                    present(right) => { return false },
                    none => { return true }
                }
            }
        }
        true
    }
    mut fn ne<I: Iterator<Item = Self.Item>>(other: take I): bool where Self.Item: PartialEq {
        !self.eq(other)
    }
    mut fn lt<I: Iterator<Item = Self.Item>>(other: take I): bool where Self.Item: PartialOrd {
        match self.partial_cmp(other) {
            present(order) => order.is_lt(),
            none => false
        }
    }
    mut fn le<I: Iterator<Item = Self.Item>>(other: take I): bool where Self.Item: PartialOrd {
        match self.partial_cmp(other) {
            present(order) => order.is_le(),
            none => false
        }
    }
    mut fn gt<I: Iterator<Item = Self.Item>>(other: take I): bool where Self.Item: PartialOrd {
        match self.partial_cmp(other) {
            present(order) => order.is_gt(),
            none => false
        }
    }
    mut fn ge<I: Iterator<Item = Self.Item>>(other: take I): bool where Self.Item: PartialOrd {
        match self.partial_cmp(other) {
            present(order) => order.is_ge(),
            none => false
        }
    }
    mut fn is_sorted(): bool where Self.Item: PartialOrd {
        var previous = self.next()
        while true {
            match take self.next() {
                present(item) => match take previous {
                    present(before) => match before.partial_cmp(read item) {
                        present(order) => {
                            if order.is_gt() { return false }
                            previous = present(item)
                        },
                        none => { return false }
                    },
                    none => { previous = present(item) }
                },
                none => { break }
            }
        }
        true
    }
    mut fn is_sorted_by<F: mut fn(read Self.Item, read Self.Item): bool>(compare: mut F): bool {
        var previous = self.next()
        while true {
            match take self.next() {
                present(item) => match take previous {
                    present(before) => {
                        if !compare(read before, read item) { return false }
                        previous = present(item)
                    },
                    none => { previous = present(item) }
                },
                none => { break }
            }
        }
        true
    }
    mut fn is_sorted_by_key<K: PartialOrd, F: mut fn(read Self.Item): K>(key: mut F): bool {
        var previous: K? = match take self.next() {
            present(item) => present(key(read item)),
            none => none
        }
        while true {
            match take self.next() {
                present(item) => {
                    let item_key = key(read item)
                    match take previous {
                        present(before) => match before.partial_cmp(read item_key) {
                            present(order) => {
                                if order.is_gt() { return false }
                                previous = present(item_key)
                            },
                            none => { return false }
                        },
                        none => { previous = present(item_key) }
                    }
                },
                none => { break }
            }
        }
        true
    }
    mut fn partition<B: Default + ExtendItems<Self.Item>, F: mut fn(read Self.Item): bool>(
        test: mut F
    ): (B, B) {
        var matched = B.(Default).default()
        var rejected = B.(Default).default()
        while true {
            match take self.next() {
                present(item) => {
                    if test(read item) {
                        matched.extend(once(item))
                    } else {
                        rejected.extend(once(item))
                    }
                },
                none => { break }
            }
        }
        (matched, rejected)
    }
    mut fn unzip<A, B, Left: Default + ExtendItems<A>, Right: Default + ExtendItems<B>>(): (Left, Right)
        where Self.Item = (A, B) {
        var left = Left.(Default).default()
        var right = Right.(Default).default()
        while true {
            match take self.next() {
                present(pair) => {
                    left.extend(once(pair.0))
                    right.extend(once(pair.1))
                },
                none => { break }
            }
        }
        (left, right)
    }
    take fn inspect<F: mut fn(read Self.Item): Unit>(f: take F): Inspected<Self, F> { Inspected(self, f) }
    take fn fuse(): Fused<Self> { Fused(self, false) }
    take fn cycle(): Cycled<Self> where Self: Clone {
        let original = self.clone()
        Cycled(original, self, false, false)
    }
    take fn collect<C: FromItems<Self.Item>>(): C { C.(FromItems<Self.Item>).from_iter(self) }
    take fn sum(): Self.Item where Self.Item: Sum {
        var source = self
        var total = Self.Item.(Sum).zero()
        while true {
            match take source.next() { present(item) => { total = total.plus(item) }, none => { break } }
        }
        total
    }
    take fn product(): Self.Item where Self.Item: Product {
        var source = self
        var total = Self.Item.(Product).one()
        while true {
            match take source.next() { present(item) => { total = total.times(item) }, none => { break } }
        }
        total
    }
    // The last of several equal maxima is returned, the first of several equal minima.
    take fn max(): Self.Item? where Self.Item: Ord {
        var source = self
        var best = source.next()
        while true {
            match take source.next() {
                present(item) => match take best {
                    present(current) => { best = present(super.cmp.max(current, item)) },
                    none => { best = present(item) }
                },
                none => { break }
            }
        }
        best
    }
    take fn min(): Self.Item? where Self.Item: Ord {
        var source = self
        var best = source.next()
        while true {
            match take source.next() {
                present(item) => match take best {
                    present(current) => { best = present(super.cmp.min(current, item)) },
                    none => { best = present(item) }
                },
                none => { break }
            }
        }
        best
    }
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

// Iterators whose remaining length is known exactly.
pub interface ExactSizeIterator: Iterator {
    fn len(): usize;
    fn size_hint(): (usize, usize?) {
        let length = self.len()
        (length, present(length))
    }
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
    mut fn rfind<F: mut fn(read Self.(Iterator).Item): bool>(test: mut F): Self.(Iterator).Item? {
        while true {
            match take self.next_back() {
                present(item) => { if test(read item) { return present(item) } },
                none => { break }
            }
        }
        none
    }
    mut fn rposition<F: mut fn(take Self.(Iterator).Item): bool>(test: mut F): usize? {
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
    mut fn try_rfold<B, E, F: mut fn(take B, take Self.(Iterator).Item): B throws E>(
        start: take B,
        f: mut F
    ): (B throws E) {
        var accumulator = start
        while true {
            match take self.next_back() {
                present(item) => match take capture f(take accumulator, item) {
                    success(value) => { accumulator = value },
                    failure(error) => { return failure(error) }
                },
                none => { break }
            }
        }
        success(accumulator)
    }
    mut fn rfold<B, F: mut fn(take B, take Self.(Iterator).Item): B>(start: take B, f: mut F): B {
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

extend<region r, I: Iterator> ByRef<region r, I> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? { self.iter.next() }
    fn size_hint(): (usize, usize?) { self.iter.size_hint() }
}
extend<region r, I: Iterator + BidirectionalIterator> ByRef<region r, I> implements BidirectionalIterator {
    mut fn next_back(): I.Item? { self.iter.next_back() }
}
extend<region r, I: ExactSizeIterator> ByRef<region r, I> implements ExactSizeIterator {
    fn len(): usize { self.iter.len() }
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
extend<B, I: Iterator, F: mut fn(take I.Item): B> Mapped<B, I, F> implements Iterator {
    type Item = B
    mut fn next(): B? {
        match take self.iter.next() { present(item) => present(self.f(item)), none => none }
    }
}
extend<B, I: Iterator + BidirectionalIterator, F: mut fn(take I.(Iterator).Item): B> Mapped<B, I, F> implements BidirectionalIterator {
    mut fn next_back(): B? {
        match take self.iter.next_back() { present(item) => present(self.f(item)), none => none }
    }
}
extend<B, I: ExactSizeIterator, F: mut fn(take I.Item): B> Mapped<B, I, F> implements ExactSizeIterator {
    fn len(): usize { self.iter.len() }
}

pub type Filtered<I, F> { iter: I; test: F }
extend<I: Iterator, F: mut fn(read I.Item): bool> Filtered<I, F> implements Iterator {
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
extend<I: Iterator + BidirectionalIterator, F: mut fn(read I.(Iterator).Item): bool> Filtered<I, F> implements BidirectionalIterator {
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
extend<B, I: Iterator, F: mut fn(take I.Item): B?> FilterMapped<B, I, F> implements Iterator {
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
extend<B, I: Iterator + BidirectionalIterator, F: mut fn(take I.(Iterator).Item): B?> FilterMapped<B, I, F> implements BidirectionalIterator {
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
extend<B, I: Iterator, F: mut fn(take I.Item): B?> MappedWhile<B, I, F> implements Iterator {
    type Item = B
    mut fn next(): B? {
        match take self.iter.next() {
            present(item) => self.f(item),
            none => none
        }
    }
}

pub type FlatMapped<O, U, F> { outer: O; inner: U?; f: F }
extend<O: Iterator, U: Iterator, F: mut fn(take O.Item): U> FlatMapped<O, U, F> implements Iterator {
    type Item = U.Item
    mut fn next(): U.Item? {
        while true {
            match mut self.inner {
                present(inner) => match take inner.next() {
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
extend<O: Iterator + BidirectionalIterator, U: Iterator + BidirectionalIterator, F: mut fn(take O.Item): U> FlatMapped<O, U, F> implements BidirectionalIterator {
    mut fn next_back(): U.Item? {
        while true {
            match mut self.inner {
                present(inner) => match take inner.next_back() {
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

pub type Flatten<U: Iterator, O: Iterator<Item = U>> {
    outer: O
    front: U?
    back: U?
    outer_done: bool
}

pub type Cloned<region r, T, I> { iter: I; result: Phantom<T> }
extend<region r, T: Clone, I: Iterator<Item = read T from r>> Cloned<region r, T, I> implements Iterator {
    type Item = T
    mut fn next(): T? {
        match take self.iter.next() {
            present(item) => present(item.clone()),
            none => none
        }
    }
}
extend<region r, T: Clone, I: Iterator<Item = read T from r> + ExactSizeIterator> Cloned<region r, T, I> implements ExactSizeIterator {
    fn len(): usize { self.iter.len() }
}
extend<region r, T: Clone, I: Iterator<Item = read T from r> + BidirectionalIterator> Cloned<region r, T, I> implements BidirectionalIterator {
    mut fn next_back(): T? {
        match take self.iter.next_back() {
            present(item) => present(item.clone()),
            none => none
        }
    }
}

pub type Copied<region r, T, I> { iter: I; result: Phantom<T> }
extend<region r, T: Copy, I: Iterator<Item = read T from r>> Copied<region r, T, I> implements Iterator {
    type Item = T
    mut fn next(): T? {
        match take self.iter.next() {
            present(item) => present(*item),
            none => none
        }
    }
}
extend<region r, T: Copy, I: Iterator<Item = read T from r> + ExactSizeIterator> Copied<region r, T, I> implements ExactSizeIterator {
    fn len(): usize { self.iter.len() }
}
extend<region r, T: Copy, I: Iterator<Item = read T from r> + BidirectionalIterator> Copied<region r, T, I> implements BidirectionalIterator {
    mut fn next_back(): T? {
        match take self.iter.next_back() {
            present(item) => present(*item),
            none => none
        }
    }
}

pub type Scanned<B, I, S, F> { iter: I; state: S; f: F; result: Phantom<B> }
extend<B, I: Iterator, S, F: mut fn(mut S, take I.Item): B?> Scanned<B, I, S, F> implements Iterator {
    type Item = B
    mut fn next(): B? {
        match take self.iter.next() {
            present(item) => self.f(mut self.state, item),
            none => none
        }
    }
}
extend<U: Iterator, O: Iterator<Item = U>> Flatten<U, O> implements Iterator {
    type Item = U.Item
    mut fn next(): U.Item? {
        while true {
            match mut self.front {
                present(inner) => match take inner.next() {
                    present(item) => { return present(item) },
                    none => { self.front = none }
                },
                none => {}
            }
            if self.outer_done {
                match mut self.back {
                    present(inner) => match take inner.next() {
                        present(item) => { return present(item) },
                        none => { self.back = none; return none }
                    },
                    none => { return none }
                }
            }
            match take self.outer.next() {
                present(inner) => { self.front = present(inner) },
                none => { self.outer_done = true }
            }
        }
        none
    }
}
extend<U: Iterator + BidirectionalIterator, O: Iterator<Item = U> + BidirectionalIterator> Flatten<U, O> implements BidirectionalIterator {
    mut fn next_back(): U.Item? {
        while true {
            match mut self.back {
                present(inner) => match take inner.next_back() {
                    present(item) => { return present(item) },
                    none => { self.back = none }
                },
                none => {}
            }
            if self.outer_done {
                match mut self.front {
                    present(inner) => match take inner.next_back() {
                        present(item) => { return present(item) },
                        none => { self.front = none; return none }
                    },
                    none => { return none }
                }
            }
            match take self.outer.next_back() {
                present(inner) => { self.back = present(inner) },
                none => { self.outer_done = true }
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
extend<I: ExactSizeIterator> Enumerated<I> implements ExactSizeIterator {
    fn len(): usize { self.iter.len() }
}
extend<I: ExactSizeIterator + BidirectionalIterator> Enumerated<I> implements BidirectionalIterator {
    mut fn next_back(): (usize, I.(Iterator).Item)? {
        match take self.iter.next_back() {
            present(item) => present((self.index + self.iter.len(), item)),
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
extend<A: ExactSizeIterator, B: ExactSizeIterator> Zipped<A, B> implements ExactSizeIterator {
    fn len(): usize {
        let first = self.first.len()
        let second = self.second.len()
        if first < second { first } else { second }
    }
}
extend<A: Iterator + ExactSizeIterator + BidirectionalIterator,
       B: Iterator + ExactSizeIterator + BidirectionalIterator> Zipped<A, B>
    implements BidirectionalIterator {
    mut fn next_back(): (A.(Iterator).Item, B.(Iterator).Item)? {
        let first_len = self.first.len()
        let second_len = self.second.len()
        if first_len < second_len {
            let _discarded = self.second.nth_back(second_len - first_len - 1usize)
        } else if second_len < first_len {
            let _discarded = self.first.nth_back(first_len - second_len - 1usize)
        }
        match take self.first.next_back() {
            present(first) => match take self.second.next_back() {
                present(second) => present((first, second)),
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
            present(rest) => match take rest.next_back() {
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
extend<I: ExactSizeIterator> Limited<I> implements ExactSizeIterator {
    fn len(): usize {
        let available = self.iter.len()
        if available < self.remaining { available } else { self.remaining }
    }
}
extend<I: ExactSizeIterator + BidirectionalIterator> Limited<I> implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? {
        if self.remaining == 0usize { return none }
        let available = self.iter.len()
        if available > self.remaining {
            let excess = available - self.remaining
            let _ = self.iter.nth_back(excess - 1usize)
        }
        match take self.iter.next_back() {
            present(item) => {
                self.remaining -= 1usize
                present(item)
            },
            none => none
        }
    }
}
extend<I: Iterator> Limited<I> {
    pub fn limit(): usize { self.remaining }
    pub mut fn set_limit(limit: usize): Unit { self.remaining = limit }
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
extend<I: ExactSizeIterator> Skipped<I> implements ExactSizeIterator {
    fn len(): usize {
        let available = self.iter.len()
        if available < self.pending { 0usize } else { available - self.pending }
    }
}
extend<I: ExactSizeIterator + BidirectionalIterator> Skipped<I> implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? {
        if self.iter.len() <= self.pending { return none }
        self.iter.next_back()
    }
}

pub type TakenWhile<I, F> { iter: I; test: F; done: bool }
extend<I: Iterator, F: mut fn(read I.Item): bool> TakenWhile<I, F> implements Iterator {
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
extend<I: Iterator, F: mut fn(read I.Item): bool> SkippedWhile<I, F> implements Iterator {
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

extend<I: ExactSizeIterator> Stepped<I> implements ExactSizeIterator {
    fn len(): usize {
        let remaining = self.iter.len()
        if self.first {
            if remaining == 0usize { 0usize } else { 1usize + (remaining - 1usize) / self.step }
        } else {
            remaining / self.step
        }
    }
}
// Trailing items that no step lands on are discarded before taking from the back.
extend<I: ExactSizeIterator + BidirectionalIterator> Stepped<I> implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? {
        let remaining = self.iter.len()
        if self.first {
            if remaining == 0usize { return none }
            self.iter.nth_back((remaining - 1usize) % self.step)
        } else {
            self.iter.nth_back(remaining % self.step)
        }
    }
}

pub type Inspected<I, F> { iter: I; f: F }
extend<I: Iterator, F: mut fn(read I.Item): Unit> Inspected<I, F> implements Iterator {
    type Item = I.Item
    mut fn next(): I.Item? {
        match take self.iter.next() {
            present(item) => { self.f(read item); present(item) },
            none => none
        }
    }
}
extend<I: ExactSizeIterator, F: mut fn(read I.Item): Unit> Inspected<I, F> implements ExactSizeIterator {
    fn len(): usize { self.iter.len() }
}
extend<I: BidirectionalIterator, F: mut fn(read I.(Iterator).Item): Unit> Inspected<I, F> implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? {
        match take self.iter.next_back() {
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
extend<I: ExactSizeIterator> Fused<I> implements ExactSizeIterator {
    fn len(): usize { if self.done { 0usize } else { self.iter.len() } }
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
extend<I: ExactSizeIterator + BidirectionalIterator> Reversed<I> implements ExactSizeIterator {
    fn len(): usize { self.iter.len() }
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
    pub mut fn peek_mut(): (mut I.Item from self)? {
        if !self.filled {
            self.slot = present(self.iter.next())
            self.filled = true
        }
        match mut self.slot {
            present(held) => match mut held {
                present(item) => present(mut item),
                none => none
            },
            none => none
        }
    }
    pub mut fn next_if(test: fn(read I.Item): bool): I.Item? {
        match self.peek() {
            present(item) => if test(item) { self.next() } else { none },
            none => none
        }
    }
    pub mut fn next_if_eq(expected: read I.Item): I.Item? where I.Item: PartialEq {
        match self.peek() {
            present(item) => if item == expected { self.next() } else { none },
            none => none
        }
    }
    pub mut fn next_if_map<B, F: fn(read I.Item): B?>(map: take F): B? {
        match self.peek() {
            present(item) => match map(item) {
                present(mapped) => {
                    let _taken = self.next()
                    present(mapped)
                },
                none => none
            },
            none => none
        }
    }
    pub mut fn next_if_map_mut<B, F: fn(mut I.Item): B?>(map: take F): B? {
        match self.peek_mut() {
            present(item) => match map(mut item) {
                present(mapped) => {
                    let _taken = self.next()
                    present(mapped)
                },
                none => none
            },
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
extend<I: ExactSizeIterator> Peekable<I> implements ExactSizeIterator {
    fn len(): usize {
        let cached = if self.filled {
            match self.slot {
                present(held) => match held { present(_) => 1usize, none => 0usize },
                none => 0usize
            }
        } else {
            0usize
        }
        self.iter.len() + cached
    }
}

// Sources.
pub type Once<T> { value: T? }
extend<T> Once<T> implements Iterator {
    type Item = T
    mut fn next(): T? { self.value.take_value() }
}
extend<T> Once<T> implements ExactSizeIterator {
    fn len(): usize { if self.value.is_present() { 1usize } else { 0usize } }
}
extend<T> Once<T> implements BidirectionalIterator {
    mut fn next_back(): T? { self.value.take_value() }
}
pub fn once<T>(value: take T): Once<T> { Once(present(value)) }

pub type Empty<T> { marker: Phantom<T> }
extend<T> Empty<T> implements Iterator {
    type Item = T
    mut fn next(): T? { none }
}
extend<T> Empty<T> implements ExactSizeIterator {
    fn len(): usize { 0usize }
}
extend<T> Empty<T> implements BidirectionalIterator {
    mut fn next_back(): T? { none }
}
pub fn empty<T>(): Empty<T> { Empty(Phantom<T>()) }

// Calls `f` on each poll; returning none does not latch the iterator as fused.
pub type FromFn<T, F> { f: F; item: Phantom<T> }
extend<T, F: mut fn(): T?> FromFn<T, F> implements Iterator {
    type Item = T
    mut fn next(): T? { self.f() }
}
pub fn from_fn<T, F: mut fn(): T?>(f: take F): FromFn<T, F> { FromFn(f, Phantom<T>()) }

// Endless iterator calling `f` for every item.
pub type RepeatWith<T, F> { f: F; item: Phantom<T> }
extend<T, F: mut fn(): T> RepeatWith<T, F> implements Iterator {
    type Item = T
    mut fn next(): T? { present(self.f()) }
}
pub fn repeat_with<T, F: mut fn(): T>(f: take F): RepeatWith<T, F> { RepeatWith(f, Phantom<T>()) }

pub type Repeated<T> { value: T }
extend<T: Clone> Repeated<T> implements Iterator {
    type Item = T
    mut fn next(): T? { present(self.value.clone()) }
}
pub fn repeat<T: Clone>(value: take T): Repeated<T> { Repeated(value) }

pub type Successors<T, F> { current: T?; step: F }
extend<T, F: mut fn(read T): T?> Successors<T, F> implements Iterator {
    type Item = T
    mut fn next(): T? {
        match take self.current.take_value() {
            present(value) => {
                self.current = self.step(read value)
                present(value)
            },
            none => none
        }
    }
}
pub fn successors<T, F: mut fn(read T): T?>(first: take T?, step: take F): Successors<T, F> {
    Successors(first, step)
}

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
pub type Range<T> { pub start: T; pub end: T }
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
pub type RangeInclusive<T> { pub start: T; pub end: T; done: bool }
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
extend i128 implements Sum {
    static fn zero(): i128 { 0i128 }
    fn plus(other: take i128): i128 { self + other }
}
extend i128 implements Product {
    static fn one(): i128 { 1i128 }
    fn times(other: take i128): i128 { self * other }
}
extend u128 implements Sum {
    static fn zero(): u128 { 0u128 }
    fn plus(other: take u128): u128 { self + other }
}
extend u128 implements Product {
    static fn one(): u128 { 1u128 }
    fn times(other: take u128): u128 { self * other }
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
extend f32 implements Sum {
    static fn zero(): f32 { 0.0f32 }
    fn plus(other: take f32): f32 { self + other }
}
extend f32 implements Product {
    static fn one(): f32 { 1.0f32 }
    fn times(other: take f32): f32 { self * other }
}
extend f64 implements Sum {
    static fn zero(): f64 { 0.0f64 }
    fn plus(other: take f64): f64 { self + other }
}
extend f64 implements Product {
    static fn one(): f64 { 1.0f64 }
    fn times(other: take f64): f64 { self * other }
}

// Iterators that keep returning none once `next` has returned none. Adapters
// forward the marker when the wrapped iterators carry it.
pub interface FusedIterator: Iterator {}
extend<I: Iterator> Fused<I> implements FusedIterator {}
extend<T> Empty<T> implements FusedIterator {}
extend<T> Once<T> implements FusedIterator {}
extend<T: Clone> Repeated<T> implements FusedIterator {}
extend<T, F: mut fn(): T> RepeatWith<T, F> implements FusedIterator {}
extend<T, F: mut fn(read T): T?> Successors<T, F> implements FusedIterator {}
extend<T: Step> Range<T> implements FusedIterator {}
extend<T: Step> RangeFrom<T> implements FusedIterator {}
extend<T: Step> RangeInclusive<T> implements FusedIterator {}
extend<region r, I: FusedIterator> ByRef<region r, I> implements FusedIterator {}
extend<B, I: FusedIterator, F: mut fn(take I.Item): B> Mapped<B, I, F> implements FusedIterator {}
extend<I: FusedIterator, F: mut fn(read I.Item): bool> Filtered<I, F> implements FusedIterator {}
extend<B, I: FusedIterator, F: mut fn(take I.Item): B?> FilterMapped<B, I, F> implements FusedIterator {}
extend<region r, T: Clone, I: Iterator<Item = read T from r> + FusedIterator> Cloned<region r, T, I> implements FusedIterator {}
extend<region r, T: Copy, I: Iterator<Item = read T from r> + FusedIterator> Copied<region r, T, I> implements FusedIterator {}
extend<I: FusedIterator> Enumerated<I> implements FusedIterator {}
extend<A: FusedIterator, B: FusedIterator> Zipped<A, B> implements FusedIterator {}
extend<T, A: Iterator<Item = T> + FusedIterator, B: Iterator<Item = T> + FusedIterator> Chained<A, B> implements FusedIterator {}
extend<I: FusedIterator> Limited<I> implements FusedIterator {}
extend<I: FusedIterator> Skipped<I> implements FusedIterator {}
extend<I: FusedIterator, F: mut fn(read I.Item): bool> TakenWhile<I, F> implements FusedIterator {}
extend<I: FusedIterator, F: mut fn(read I.Item): bool> SkippedWhile<I, F> implements FusedIterator {}
extend<I: FusedIterator> Stepped<I> implements FusedIterator {}
extend<I: FusedIterator, F: mut fn(read I.Item): Unit> Inspected<I, F> implements FusedIterator {}
extend<I: Iterator + BidirectionalIterator + FusedIterator> Reversed<I> implements FusedIterator {}
extend<I: FusedIterator> Peekable<I> implements FusedIterator {}

// Explicit duplication of an adapter duplicates the wrapped iterators and any
// callbacks; closures are cloned only where the callback type is `Clone`.
extend<B, I: Clone, F: Clone> Mapped<B, I, F> implements Clone {
    fn clone(): Mapped<B, I, F> { Mapped(self.iter.clone(), self.f.clone(), Phantom<B>()) }
}
extend<I: Clone, F: Clone> Filtered<I, F> implements Clone {
    fn clone(): Filtered<I, F> { Filtered(self.iter.clone(), self.test.clone()) }
}
extend<B, I: Clone, F: Clone> FilterMapped<B, I, F> implements Clone {
    fn clone(): FilterMapped<B, I, F> { FilterMapped(self.iter.clone(), self.f.clone(), Phantom<B>()) }
}
extend<region r, T, I: Clone> Cloned<region r, T, I> implements Clone {
    fn clone(): Cloned<region r, T, I> { Cloned(self.iter.clone(), Phantom<T>()) }
}
extend<region r, T, I: Clone> Copied<region r, T, I> implements Clone {
    fn clone(): Copied<region r, T, I> { Copied(self.iter.clone(), Phantom<T>()) }
}
extend<I: Clone> Enumerated<I> implements Clone {
    fn clone(): Enumerated<I> { Enumerated(self.iter.clone(), self.index) }
}
extend<A: Clone, B: Clone> Zipped<A, B> implements Clone {
    fn clone(): Zipped<A, B> { Zipped(self.first.clone(), self.second.clone()) }
}
extend<A: Clone, B: Clone> Chained<A, B> implements Clone {
    fn clone(): Chained<A, B> { Chained(self.first.clone(), self.second.clone(), self.first_live) }
}
extend<I: Clone> Limited<I> implements Clone {
    fn clone(): Limited<I> { Limited(self.iter.clone(), self.remaining) }
}
extend<I: Clone> Skipped<I> implements Clone {
    fn clone(): Skipped<I> { Skipped(self.iter.clone(), self.pending) }
}
extend<I: Clone, F: Clone> TakenWhile<I, F> implements Clone {
    fn clone(): TakenWhile<I, F> { TakenWhile(self.iter.clone(), self.test.clone(), self.done) }
}
extend<I: Clone, F: Clone> SkippedWhile<I, F> implements Clone {
    fn clone(): SkippedWhile<I, F> { SkippedWhile(self.iter.clone(), self.test.clone(), self.started) }
}
extend<I: Clone> Stepped<I> implements Clone {
    fn clone(): Stepped<I> { Stepped(self.iter.clone(), self.step, self.first) }
}
extend<I: Clone, F: Clone> Inspected<I, F> implements Clone {
    fn clone(): Inspected<I, F> { Inspected(self.iter.clone(), self.f.clone()) }
}
extend<I: Clone> Fused<I> implements Clone {
    fn clone(): Fused<I> { Fused(self.iter.clone(), self.done) }
}
extend<I: Clone> Cycled<I> implements Clone {
    fn clone(): Cycled<I> { Cycled(self.original.clone(), self.iter.clone(), self.yielded, self.done) }
}
extend<I: Clone> Reversed<I> implements Clone {
    fn clone(): Reversed<I> { Reversed(self.iter.clone()) }
}
extend<T: Clone> Once<T> implements Clone {
    fn clone(): Once<T> { Once(self.value.clone()) }
}
extend<T> Empty<T> implements Clone {
    fn clone(): Empty<T> { Empty(Phantom<T>()) }
}
extend<T: Clone> Repeated<T> implements Clone {
    fn clone(): Repeated<T> { Repeated(self.value.clone()) }
}
extend<T, F: Clone> RepeatWith<T, F> implements Clone {
    fn clone(): RepeatWith<T, F> { RepeatWith(self.f.clone(), Phantom<T>()) }
}
extend<T, F: Clone> FromFn<T, F> implements Clone {
    fn clone(): FromFn<T, F> { FromFn(self.f.clone(), Phantom<T>()) }
}
extend<T: Clone, F: Clone> Successors<T, F> implements Clone {
    fn clone(): Successors<T, F> { Successors(self.current.clone(), self.step.clone()) }
}

// The default adapter wraps default iterators and has consumed nothing.
extend<T> Empty<T> implements Default {
    static fn default(): Empty<T> { empty<T>() }
}
extend<region r, T, I: Default> Cloned<region r, T, I> implements Default {
    static fn default(): Cloned<region r, T, I> { Cloned(I.(Default).default(), Phantom<T>()) }
}
extend<region r, T, I: Default> Copied<region r, T, I> implements Default {
    static fn default(): Copied<region r, T, I> { Copied(I.(Default).default(), Phantom<T>()) }
}
extend<I: Default> Enumerated<I> implements Default {
    static fn default(): Enumerated<I> { Enumerated(I.(Default).default(), 0usize) }
}
extend<A: Default, B: Default> Zipped<A, B> implements Default {
    static fn default(): Zipped<A, B> { Zipped(A.(Default).default(), B.(Default).default()) }
}
extend<A: Default, B: Default> Chained<A, B> implements Default {
    static fn default(): Chained<A, B> {
        Chained(A.(Default).default(), present(B.(Default).default()), true)
    }
}
extend<I: Default> Limited<I> implements Default {
    static fn default(): Limited<I> { Limited(I.(Default).default(), 0usize) }
}
extend<I: Default> Skipped<I> implements Default {
    static fn default(): Skipped<I> { Skipped(I.(Default).default(), 0usize) }
}
extend<I: Default> Fused<I> implements Default {
    static fn default(): Fused<I> { Fused(I.(Default).default(), false) }
}
extend<I: Default> Reversed<I> implements Default {
    static fn default(): Reversed<I> { Reversed(I.(Default).default()) }
}
extend<T: Step + Default> Range<T> implements Default {
    static fn default(): Range<T> { Range(T.(Default).default(), T.(Default).default()) }
}

// Debug names the adapter and shows the wrapped iterators; callbacks are not
// printed because closures have no formatting.
extend<B, I: fmt.Debug, F> Mapped<B, I, F> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Mapped")
        try fields.field("iter", read self.iter)
        try fields.finish()
    }
}
extend<I: fmt.Debug, F> Filtered<I, F> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Filtered")
        try fields.field("iter", read self.iter)
        try fields.finish()
    }
}
extend<B, I: fmt.Debug, F> FilterMapped<B, I, F> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("FilterMapped")
        try fields.field("iter", read self.iter)
        try fields.finish()
    }
}
extend<region r, T, I: fmt.Debug> Cloned<region r, T, I> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Cloned")
        try fields.field("iter", read self.iter)
        try fields.finish()
    }
}
extend<region r, T, I: fmt.Debug> Copied<region r, T, I> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Copied")
        try fields.field("iter", read self.iter)
        try fields.finish()
    }
}
extend<I: fmt.Debug> Enumerated<I> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Enumerated")
        try fields.field("iter", read self.iter)
        try fields.field("count", read self.index)
        try fields.finish()
    }
}
extend<A: fmt.Debug, B: fmt.Debug> Zipped<A, B> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Zipped")
        try fields.field("first", read self.first)
        try fields.field("second", read self.second)
        try fields.finish()
    }
}
extend<A: fmt.Debug, B: fmt.Debug> Chained<A, B> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Chained")
        try fields.field("first", read self.first)
        try fields.field("second", read self.second)
        try fields.finish()
    }
}
extend<I: fmt.Debug> Limited<I> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Limited")
        try fields.field("iter", read self.iter)
        try fields.field("remaining", read self.remaining)
        try fields.finish()
    }
}
extend<I: fmt.Debug> Skipped<I> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Skipped")
        try fields.field("iter", read self.iter)
        try fields.field("pending", read self.pending)
        try fields.finish()
    }
}
extend<I: fmt.Debug, F> TakenWhile<I, F> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("TakenWhile")
        try fields.field("iter", read self.iter)
        try fields.field("done", read self.done)
        try fields.finish()
    }
}
extend<I: fmt.Debug, F> SkippedWhile<I, F> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("SkippedWhile")
        try fields.field("iter", read self.iter)
        try fields.field("started", read self.started)
        try fields.finish()
    }
}
extend<I: fmt.Debug> Stepped<I> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Stepped")
        try fields.field("iter", read self.iter)
        try fields.field("step", read self.step)
        try fields.field("first", read self.first)
        try fields.finish()
    }
}
extend<I: fmt.Debug, F> Inspected<I, F> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Inspected")
        try fields.field("iter", read self.iter)
        try fields.finish()
    }
}
extend<I: fmt.Debug> Fused<I> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Fused")
        try fields.field("iter", read self.iter)
        try fields.field("done", read self.done)
        try fields.finish()
    }
}
extend<I: fmt.Debug> Cycled<I> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Cycled")
        try fields.field("original", read self.original)
        try fields.field("iter", read self.iter)
        try fields.finish()
    }
}
extend<I: fmt.Debug> Reversed<I> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Reversed")
        try fields.field("iter", read self.iter)
        try fields.finish()
    }
}
extend<T: fmt.Debug> Once<T> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Once")
        try fields.field("value", read self.value)
        try fields.finish()
    }
}
extend<T> Empty<T> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try f.write_str("Empty") }
}
extend<T: fmt.Debug> Repeated<T> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        var fields = try f.debug_struct("Repeated")
        try fields.field("value", read self.value)
        try fields.finish()
    }
}
extend<T: Step + fmt.Debug> Range<T> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.start, mut f)
        try f.write_str("..")
        try T.(fmt.Debug).fmt(self.end, mut f)
    }
}
extend<T: Step + fmt.Debug> RangeInclusive<T> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.start, mut f)
        try f.write_str("..=")
        try T.(fmt.Debug).fmt(self.end, mut f)
    }
}
extend<T: Step + fmt.Debug> RangeFrom<T> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.start, mut f)
        try f.write_str("..")
    }
}
