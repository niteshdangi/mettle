// Iteration. The compiler recognizes `Iterator`, `OwnedIterable`, `Iterable`
// and `MutableIterable` by canonical path for `for` loops. Adapters are lazy: they
// pull from the wrapped iterator only when `next` is called, and consuming
// methods stop at the first decisive item.
import super.cmp.Ord
import super.cmp.PartialEq
import super.cmp.PartialOrd
import super.option
import super.cmp.Ordering
import super.clone.Clone
import super.default.Default

pub interface Iterator: Sized {
    type Item;
    mut fn next(): Self.Item?;

    // Bounds on the remaining length: `(lower, upper)`; `upper` is none when unknown.
    fn size_hint(): (usize, usize?) { (0usize, none) }
    fn by_ref<region r>(receiver self: mut Self from r): mut Self from r { mut self }

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
    mut fn fold<B, F: mut fn(take B, take Self.Item): B>(start: take B, f: take F): B {
        var callable = f
        var accumulator = start
        while true {
            match take self.next() {
                present(item) => { accumulator = callable(take accumulator, item) },
                none => { break }
            }
        }
        accumulator
    }
    take fn sum<S: Sum<Self.Item>>(): S {
        var source = self
        var total = S.(Sum<Self.Item>).zero()
        while true {
            match take source.next() {
                present(item) => { total = total.plus(item) },
                none => { break }
            }
        }
        total
    }
    take fn product<P: Product<Self.Item>>(): P {
        var source = self
        var total = P.(Product<Self.Item>).one()
        while true {
            match take source.next() {
                present(item) => { total = total.times(item) },
                none => { break }
            }
        }
        total
    }
    mut fn for_each<F: mut fn(take Self.Item): Unit>(f: take F): Unit {
        var callable = f
        while true {
            match take self.next() { present(item) => { callable(item) }, none => { break } }
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
    mut fn any<F: mut fn(take Self.Item): bool>(test: take F): bool {
        var predicate = test
        while true {
            match take self.next() {
                present(item) => { if predicate(item) { return true } },
                none => { break }
            }
        }
        false
    }
    // Stops at the first item for which `test` fails.
    mut fn all<F: mut fn(take Self.Item): bool>(test: take F): bool {
        var predicate = test
        while true {
            match take self.next() {
                present(item) => { if !predicate(item) { return false } },
                none => { break }
            }
        }
        true
    }
    mut fn find<F: mut fn(read Self.Item): bool>(test: take F): Self.Item? {
        var predicate = test
        while true {
            match take self.next() {
                present(item) => { if predicate(read item) { return present(item) } },
                none => { break }
            }
        }
        none
    }
    mut fn position<F: mut fn(take Self.Item): bool>(test: take F): usize? {
        var predicate = test
        var index = 0usize
        while true {
            match take self.next() {
                present(item) => {
                    if predicate(item) { return present(index) }
                    index += 1usize
                },
                none => { break }
            }
        }
        none
    }
    mut fn find_map<B, F: mut fn(take Self.Item): B?>(f: take F): B? {
        var callable = f
        while true {
            match take self.next() {
                present(item) => { match take callable(item) { present(found) => { return present(found) }, none => {} } },
                none => { break }
            }
        }
        none
    }
    mut fn min_by<F: mut fn(read Self.Item, read Self.Item): Ordering>(compare: take F): Self.Item? {
        var comparator = compare
        var best = self.next()
        while true {
            match take self.next() {
                present(item) => match take best {
                    present(current) => {
                        if comparator(read item, read current).is_lt() {
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
    mut fn max_by<F: mut fn(read Self.Item, read Self.Item): Ordering>(compare: take F): Self.Item? {
        var comparator = compare
        var best = self.next()
        while true {
            match take self.next() {
                present(item) => match take best {
                    present(current) => {
                        if !comparator(read item, read current).is_lt() {
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
    mut fn min_by_key<K: Ord, F: mut fn(read Self.Item): K>(key: take F): Self.Item? {
        var key_of = key
        var best: (Self.Item, K)? = match take self.next() {
            present(item) => {
                let item_key = key_of(read item)
                present((item, item_key))
            },
            none => none
        }
        while true {
            match take self.next() {
                present(item) => {
                    let item_key = key_of(read item)
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
    mut fn max_by_key<K: Ord, F: mut fn(read Self.Item): K>(key: take F): Self.Item? {
        var key_of = key
        var best: (Self.Item, K)? = match take self.next() {
            present(item) => {
                let item_key = key_of(read item)
                present((item, item_key))
            },
            none => none
        }
        while true {
            match take self.next() {
                present(item) => {
                    let item_key = key_of(read item)
                    match take best {
                        present((current, current_key)) => {
                            if !item_key.cmp(read current_key).is_lt() {
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
    mut fn reduce<F: mut fn(take Self.Item, take Self.Item): Self.Item>(f: take F): Self.Item? {
        var callable = f
        var accumulator = self.next()
        while true {
            match take self.next() {
                present(item) => {
                    match take accumulator {
                        present(value) => { accumulator = present(callable(value, item)) },
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
        FlatMapped(self, none, none, false, f)
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
    take fn inspect<F: mut fn(read Self.Item): Unit>(f: take F): Inspected<Self, F> { Inspected(self, f) }
    take fn fuse(): Fused<Self> { Fused(self, false) }
    take fn cycle(): Cycled<Self> where Self: Clone {
        let original = self.clone()
        Cycled(original, self, false, false)
    }
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
    // Lexicographic comparison of two sequences; the shorter one orders first.
    take fn cmp<O: OwnedIterable<Item = Self.Item>>(other: take O): Ordering where Self.Item: Ord {
        var left = self
        var right = O.(OwnedIterable).into_iter(other)
        while true {
            match take left.next() {
                present(a) => match take right.next() {
                    present(b) => {
                        let order = a.cmp(read b)
                        if !order.is_eq() { return order }
                    },
                    none => { return Ordering.Greater }
                },
                none => {
                    if right.next().is_present() { return Ordering.Less }
                    return Ordering.Equal
                }
            }
        }
        Ordering.Equal
    }
    // Returns none as soon as an incomparable pair is met.
    take fn partial_cmp<O: OwnedIterable<Item = Self.Item>>(other: take O): Ordering? where Self.Item: PartialOrd {
        var left = self
        var right = O.(OwnedIterable).into_iter(other)
        while true {
            match take left.next() {
                present(a) => match take right.next() {
                    present(b) => match a.partial_cmp(read b) {
                        present(order) => { if !order.is_eq() { return present(order) } },
                        none => { return none }
                    },
                    none => { return present(Ordering.Greater) }
                },
                none => {
                    if right.next().is_present() { return present(Ordering.Less) }
                    return present(Ordering.Equal)
                }
            }
        }
        present(Ordering.Equal)
    }
    take fn eq<O: OwnedIterable<Item = Self.Item>>(other: take O): bool where Self.Item: PartialEq {
        var left = self
        var right = O.(OwnedIterable).into_iter(other)
        while true {
            match take left.next() {
                present(a) => match take right.next() {
                    present(b) => { if !a.eq(read b) { return false } },
                    none => { return false }
                },
                none => { return !right.next().is_present() }
            }
        }
        true
    }
    take fn ne<O: OwnedIterable<Item = Self.Item>>(other: take O): bool where Self.Item: PartialEq {
        !self.eq(other)
    }
    take fn lt<O: OwnedIterable<Item = Self.Item>>(other: take O): bool where Self.Item: PartialOrd {
        match self.partial_cmp(other) { present(order) => order.is_lt(), none => false }
    }
    take fn le<O: OwnedIterable<Item = Self.Item>>(other: take O): bool where Self.Item: PartialOrd {
        match self.partial_cmp(other) { present(order) => order.is_le(), none => false }
    }
    take fn gt<O: OwnedIterable<Item = Self.Item>>(other: take O): bool where Self.Item: PartialOrd {
        match self.partial_cmp(other) { present(order) => order.is_gt(), none => false }
    }
    take fn ge<O: OwnedIterable<Item = Self.Item>>(other: take O): bool where Self.Item: PartialOrd {
        match self.partial_cmp(other) { present(order) => order.is_ge(), none => false }
    }
    take fn is_sorted(): bool where Self.Item: PartialOrd {
        var source = self
        var previous = source.next()
        while true {
            match take source.next() {
                present(item) => {
                    match take previous {
                        present(last) => { if !last.le(read item) { return false } },
                        none => {}
                    }
                    previous = present(item)
                },
                none => { break }
            }
        }
        true
    }
    take fn is_sorted_by<F: mut fn(read Self.Item, read Self.Item): bool>(compare: take F): bool {
        var comparator = compare
        var source = self
        var previous = source.next()
        while true {
            match take source.next() {
                present(item) => {
                    match take previous {
                        present(last) => { if !comparator(read last, read item) { return false } },
                        none => {}
                    }
                    previous = present(item)
                },
                none => { break }
            }
        }
        true
    }
    take fn is_sorted_by_key<K: PartialOrd, F: mut fn(read Self.Item): K>(key: take F): bool {
        var key_of = key
        var source = self
        var previous: K? = none
        while true {
            match take source.next() {
                present(item) => {
                    let item_key = key_of(read item)
                    match take previous {
                        present(last) => { if !last.le(read item_key) { return false } },
                        none => {}
                    }
                    previous = present(item_key)
                },
                none => { break }
            }
        }
        true
    }
    // Splits the items into two collections by `test`, keeping their order.
    take fn partition<B: Default + ExtendItems<Self.Item>, F: mut fn(read Self.Item): bool>(test: take F): (B, B) {
        var predicate = test
        var source = self
        var yes = B.(Default).default()
        var no = B.(Default).default()
        while true {
            match take source.next() {
                present(item) => {
                    if predicate(read item) { yes.extend(once(item)) } else { no.extend(once(item)) }
                },
                none => { break }
            }
        }
        (yes, no)
    }
    take fn unzip<A, B, Left: Default + ExtendItems<A>, Right: Default + ExtendItems<B>>(): (Left, Right)
    where Self: Iterator<Item = (A, B)> {
        var source = self
        var left = Left.(Default).default()
        var right = Right.(Default).default()
        while true {
            match take Self.(Iterator).next(mut source) {
                present(item) => {
                    let (a, b): (A, B) = item
                    left.extend(once(a))
                    right.extend(once(b))
                },
                none => { break }
            }
        }
        (left, right)
    }
    take fn collect<C: FromItems<Self.Item>>(): C { C.(FromItems<Self.Item>).from_iter(self) }
}

extend<region r, I: Iterator> mut I from r implements Iterator {
    type Item = I.Item
    fn size_hint(): (usize, usize?) {
        I.(Iterator).size_hint(read *self)
    }
    mut fn next(): I.Item? {
        I.(Iterator).next(mut *self)
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
    mut fn rfind<F: mut fn(read Self.(Iterator).Item): bool>(test: take F): Self.(Iterator).Item? {
        var predicate = test
        while true {
            match take self.next_back() {
                present(item) => { if predicate(read item) { return present(item) } },
                none => { break }
            }
        }
        none
    }
    mut fn rposition<F: mut fn(take Self.(Iterator).Item): bool>(test: take F): usize? where Self: ExactSizeIterator {
        var predicate = test
        var index = self.len()
        while true {
            match take self.next_back() {
                present(item) => {
                    index -= 1usize
                    if predicate(item) { return present(index) }
                },
                none => { return none }
            }
        }
        none
    }
    mut fn rfold<B, F: mut fn(take B, take Self.(Iterator).Item): B>(start: take B, f: take F): B {
        var callable = f
        var accumulator = start
        while true {
            match take self.next_back() {
                present(item) => { accumulator = callable(take accumulator, item) },
                none => { break }
            }
        }
        accumulator
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
    take fn rev(): Reversed<Self> { Reversed(self) }
}

pub interface ExactSizeIterator: Iterator {
    fn len(): usize {
        let bounds = self.size_hint()
        match bounds.1 {
            present(upper) => {
                if upper != bounds.0 {
                    super.panic.panic("exact iterator length bounds disagree")
                }
                upper
            },
            none => { super.panic.panic("exact iterator has no upper length bound") }
        }
    }
}

pub interface FusedIterator: Iterator {}

extend<region r, I: ExactSizeIterator> mut I from r implements ExactSizeIterator {
    fn len(): usize { I.(ExactSizeIterator).len(read *self) }
}
extend<region r, I: FusedIterator> mut I from r implements FusedIterator {}

extend<region r, I: BidirectionalIterator> mut I from r implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? {
        I.(BidirectionalIterator).next_back(mut *self)
    }
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
    fn size_hint(): (usize, usize?) { self.iter.size_hint() }
    mut fn next(): B? {
        match take self.iter.next() { present(item) => present(self.f(item)), none => none }
    }
}
extend<B, I: Iterator + BidirectionalIterator, F: mut fn(take I.(Iterator).Item): B> Mapped<B, I, F> implements BidirectionalIterator {
    mut fn next_back(): B? {
        match take self.iter.next_back() { present(item) => present(self.f(item)), none => none }
    }
}

pub type Filtered<I, F> { iter: I; test: F }
extend<I: Iterator, F: mut fn(read I.Item): bool> Filtered<I, F> implements Iterator {
    type Item = I.Item
    fn size_hint(): (usize, usize?) { (0usize, self.iter.size_hint().1) }
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
    fn size_hint(): (usize, usize?) { (0usize, self.iter.size_hint().1) }
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
    fn size_hint(): (usize, usize?) { (0usize, self.iter.size_hint().1) }
    mut fn next(): B? {
        match take self.iter.next() {
            present(item) => self.f(item),
            none => none
        }
    }
}

pub type FlatMapped<O, U, F> { outer: O; front: U?; back: U?; outer_done: bool; f: F }
extend<O: Iterator, U: Iterator, F: mut fn(take O.Item): U> FlatMapped<O, U, F> implements Iterator {
    type Item = U.Item
    fn size_hint(): (usize, usize?) {
        let front = match read self.front {
            present(inner) => inner.size_hint(),
            none => (0usize, present(0usize))
        }
        let back = match read self.back {
            present(inner) => inner.size_hint(),
            none => (0usize, present(0usize))
        }
        let outer = if self.outer_done {
            (0usize, present(0usize))
        } else { self.outer.size_hint() }
        let upper = match outer.1 {
            present(0usize) => match front.1 {
                present(a) => match back.1 {
                    present(b) => a.checked_add(b),
                    none => none
                },
                none => none
            },
            _ => none
        }
        (front.0.saturating_add(back.0), upper)
    }
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
                present(item) => { self.front = present(self.f(item)) },
                none => { self.outer_done = true }
            }
        }
        none
    }
}
extend<O: Iterator + BidirectionalIterator, U: Iterator + BidirectionalIterator, F: mut fn(take O.Item): U> FlatMapped<O, U, F> implements BidirectionalIterator {
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
                present(item) => { self.back = present(self.f(item)) },
                none => { self.outer_done = true }
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

extend<region r, T: Clone, I: BidirectionalIterator + Iterator<Item = read T from r>> Cloned<region r, T, I> implements BidirectionalIterator {
    mut fn next_back(): T? {
        match take self.iter.next_back() {
            present(item) => present(item.clone()),
            none => none
        }
    }
}
pub type Cloned<region r, T, I> { iter: I; result: Phantom<T> }
extend<region r, T: Clone, I: Iterator<Item = read T from r>> Cloned<region r, T, I> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) { self.iter.size_hint() }
    mut fn next(): T? {
        match take self.iter.next() {
            present(item) => present(item.clone()),
            none => none
        }
    }
}

extend<region r, T: Copy, I: BidirectionalIterator + Iterator<Item = read T from r>> Copied<region r, T, I> implements BidirectionalIterator {
    mut fn next_back(): T? {
        match take self.iter.next_back() {
            present(item) => present(*item),
            none => none
        }
    }
}
pub type Copied<region r, T, I> { iter: I; result: Phantom<T> }
extend<region r, T: Copy, I: Iterator<Item = read T from r>> Copied<region r, T, I> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) { self.iter.size_hint() }
    mut fn next(): T? {
        match take self.iter.next() {
            present(item) => present(*item),
            none => none
        }
    }
}

pub type Scanned<B, I, S, F> { iter: I; state: S; f: F; result: Phantom<B> }
extend<B, I: Iterator, S, F: mut fn(mut S, take I.Item): B?> Scanned<B, I, S, F> implements Iterator {
    type Item = B
    fn size_hint(): (usize, usize?) { (0usize, self.iter.size_hint().1) }
    mut fn next(): B? {
        match take self.iter.next() {
            present(item) => self.f(mut self.state, item),
            none => none
        }
    }
}
extend<U: Iterator, O: Iterator<Item = U>> Flatten<U, O> implements Iterator {
    type Item = U.Item
    fn size_hint(): (usize, usize?) {
        let front = match read self.front {
            present(inner) => inner.size_hint(),
            none => (0usize, present(0usize))
        }
        let back = match read self.back {
            present(inner) => inner.size_hint(),
            none => (0usize, present(0usize))
        }
        let outer = if self.outer_done {
            (0usize, present(0usize))
        } else { self.outer.size_hint() }
        let upper = match outer.1 {
            present(0usize) => match front.1 {
                present(a) => match back.1 {
                    present(b) => a.checked_add(b),
                    none => none
                },
                none => none
            },
            _ => none
        }
        (front.0.saturating_add(back.0), upper)
    }
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

extend<I: ExactSizeIterator + BidirectionalIterator> Enumerated<I> implements BidirectionalIterator {
    mut fn next_back(): (usize, I.(Iterator).Item)? {
        match take self.iter.next_back() {
            present(item) => present((self.index + self.iter.len(), item)),
            none => none
        }
    }
}
pub type Enumerated<I> { iter: I; index: usize }
extend<I: Iterator> Enumerated<I> implements Iterator {
    type Item = (usize, I.Item)
    fn size_hint(): (usize, usize?) { self.iter.size_hint() }
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
extend<A: ExactSizeIterator + BidirectionalIterator, B: ExactSizeIterator + BidirectionalIterator> Zipped<A, B> implements BidirectionalIterator {
    mut fn next_back(): (A.(Iterator).Item, B.(Iterator).Item)? {
        while self.first.len() > self.second.len() {
            match take self.first.next_back() {
                present(item) => {},
                none => { return none }
            }
        }
        while self.second.len() > self.first.len() {
            match take self.second.next_back() {
                present(item) => {},
                none => { return none }
            }
        }
        match take self.first.next_back() {
            present(left) => match take self.second.next_back() {
                present(right) => present((left, right)),
                none => none
            },
            none => none
        }
    }
}
pub type Zipped<A, B> { first: A; second: B }
extend<A: Iterator, B: Iterator> Zipped<A, B> implements Iterator {
    type Item = (A.Item, B.Item)
    fn size_hint(): (usize, usize?) {
        let first = self.first.size_hint()
        let second = self.second.size_hint()
        let lower = if first.0 < second.0 { first.0 } else { second.0 }
        let upper = match first.1 {
            present(a) => match second.1 {
                present(b) => present(if a < b { a } else { b }),
                none => present(a)
            },
            none => second.1
        }
        (lower, upper)
    }
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
    fn size_hint(): (usize, usize?) {
        let first = if self.first_live {
            self.first.size_hint()
        } else { (0usize, present(0usize)) }
        let second = match read self.second {
            present(rest) => rest.size_hint(),
            none => (0usize, present(0usize))
        }
        let upper = match first.1 {
            present(a) => match second.1 {
                present(b) => a.checked_add(b),
                none => none
            },
            none => none
        }
        (first.0.saturating_add(second.0), upper)
    }
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
    fn size_hint(): (usize, usize?) {
        let bounds = self.iter.size_hint()
        let lower = if bounds.0 < self.remaining { bounds.0 } else { self.remaining }
        let upper = match bounds.1 {
            present(count) => if count < self.remaining { count } else { self.remaining },
            none => self.remaining
        }
        (lower, present(upper))
    }
    mut fn next(): I.Item? {
        if self.remaining == 0usize { return none }
        self.remaining -= 1usize
        self.iter.next()
    }
}
extend<I: Iterator> Limited<I> {
    pub fn limit(): usize { self.remaining }
    pub mut fn set_limit(limit: usize): Unit { self.remaining = limit }
}

pub type Skipped<I> { iter: I; pending: usize }
extend<I: Iterator> Skipped<I> implements Iterator {
    type Item = I.Item
    fn size_hint(): (usize, usize?) {
        let bounds = self.iter.size_hint()
        let upper = match bounds.1 {
            present(count) => present(count.saturating_sub(self.pending)),
            none => none
        }
        (bounds.0.saturating_sub(self.pending), upper)
    }
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
extend<I: Iterator, F: mut fn(read I.Item): bool> TakenWhile<I, F> implements Iterator {
    type Item = I.Item
    fn size_hint(): (usize, usize?) {
        if self.done { (0usize, present(0usize)) }
        else { (0usize, self.iter.size_hint().1) }
    }
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
    fn size_hint(): (usize, usize?) {
        let bounds = self.iter.size_hint()
        (if self.started { bounds.0 } else { 0usize }, bounds.1)
    }
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

extend<I: ExactSizeIterator + BidirectionalIterator> Stepped<I> implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? {
        let count = self.iter.len()
        if count == 0usize { return none }
        let trailing = if self.first {
            (count - 1usize) % self.step
        } else { count % self.step }
        self.iter.nth_back(trailing)
    }
}
pub type Stepped<I> { iter: I; step: usize; first: bool }
fn stepped_count(count: usize, step: usize, first: bool): usize {
    count / step + if first && count % step != 0usize { 1usize } else { 0usize }
}
extend<I: Iterator> Stepped<I> implements Iterator {
    type Item = I.Item
    fn size_hint(): (usize, usize?) {
        let bounds = self.iter.size_hint()
        let upper = match bounds.1 {
            present(count) => present(stepped_count(count, self.step, self.first)),
            none => none
        }
        (stepped_count(bounds.0, self.step, self.first), upper)
    }
    mut fn next(): I.Item? {
        if self.first {
            self.first = false
            return self.iter.next()
        }
        self.iter.nth(self.step - 1usize)
    }
}

pub type Inspected<I, F> { iter: I; f: F }
extend<I: Iterator, F: mut fn(read I.Item): Unit> Inspected<I, F> implements Iterator {
    type Item = I.Item
    fn size_hint(): (usize, usize?) { self.iter.size_hint() }
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
    fn size_hint(): (usize, usize?) {
        if self.done { (0usize, present(0usize)) } else { self.iter.size_hint() }
    }
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
    fn size_hint(): (usize, usize?) {
        if self.done { return (0usize, present(0usize)) }
        let bounds = self.original.size_hint()
        if bounds.0 != 0usize { return (usize.MAX, none) }
        match bounds.1 {
            present(0usize) => (0usize, present(0usize)),
            _ => (0usize, none)
        }
    }
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
    fn size_hint(): (usize, usize?) { self.iter.size_hint() }
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
    pub mut fn next_if<F: take fn(read I.Item): bool>(test: take F): I.Item? {
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
    // Consumes the next item when `f` maps it to a value; on failure the
    // returned item is kept as the next item.
    pub mut fn next_if_map<R, F: take fn(take I.Item): R throws I.Item>(f: take F): R? {
        var callable = f
        let item = match take self.next() {
            present(item) => item,
            none => { return none }
        }
        match take capture callable(item) {
            success(value) => present(value),
            failure(rest) => {
                self.slot = present(present(rest))
                self.filled = true
                none
            }
        }
    }
    // Consumes the next item when `f` yields a value for a mutable view of it.
    pub mut fn next_if_map_mut<R, F: take fn(mut I.Item): R?>(f: take F): R? {
        var callable = f
        if !self.filled {
            self.slot = present(self.iter.next())
            self.filled = true
        }
        let found = match mut self.slot {
            present(held) => match mut held {
                present(item) => callable(mut item),
                none => none
            },
            none => none
        }
        match take found {
            present(value) => { self.next(); present(value) },
            none => none
        }
    }
}
extend<I: Iterator> Peekable<I> implements Iterator {
    type Item = I.Item
    fn size_hint(): (usize, usize?) {
        let bounds = self.iter.size_hint()
        if !self.filled { return bounds }
        match read self.slot {
            present(held) => {
                if held.is_none() { return (0usize, present(0usize)) }
                let upper = match bounds.1 {
                    present(count) => count.checked_add(1usize),
                    none => none
                }
                (bounds.0.saturating_add(1usize), upper)
            },
            none => (0usize, present(0usize))
        }
    }
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
    fn size_hint(): (usize, usize?) {
        let count = if self.value.is_present() { 1usize } else { 0usize }
        (count, present(count))
    }
}
extend<T> Once<T> implements BidirectionalIterator {
    mut fn next_back(): T? { self.next() }
}
extend<T> Once<T> implements ExactSizeIterator {}
extend<T> Once<T> implements FusedIterator {}
pub fn once<T>(value: take T): Once<T> { Once(present(value)) }

pub type Empty<T> { marker: Phantom<T> }
extend<T> Empty<T> implements Iterator {
    type Item = T
    mut fn next(): T? { none }
    fn size_hint(): (usize, usize?) { (0usize, present(0usize)) }
}
extend<T> Empty<T> implements BidirectionalIterator {
    mut fn next_back(): T? { none }
}
extend<T> Empty<T> implements ExactSizeIterator {}
extend<T> Empty<T> implements FusedIterator {}
pub fn empty<T>(): Empty<T> { Empty(Phantom<T>()) }

// Calls `f` for every item; `f` returning none ends the iteration.
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
    fn size_hint(): (usize, usize?) { (usize.MAX, none) }
    mut fn next(): T? { present(self.f()) }
}
pub fn repeat_with<T, F: mut fn(): T>(f: take F): RepeatWith<T, F> { RepeatWith(f, Phantom<T>()) }

pub type Repeated<T> { value: T }
extend<T: Clone> Repeated<T> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) { (usize.MAX, none) }
    mut fn next(): T? { present(self.value.clone()) }
}
pub fn repeat<T: Clone>(value: take T): Repeated<T> { Repeated(value) }

pub type Successors<T, F> { current: T?; step: F }
extend<T, F: mut fn(read T): T?> Successors<T, F> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) {
        if self.current.is_present() { (1usize, none) } else { (0usize, present(0usize)) }
    }
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
pub enum Bound<T> { Included(T), Excluded(T), Unbounded }
extend<T> Bound<T> {
    pub fn as_ref(): Bound<read T from self> {
        match self {
            Bound.Included(value) => Bound.Included(read value),
            Bound.Excluded(value) => Bound.Excluded(read value),
            Bound.Unbounded => Bound.Unbounded
        }
    }
    pub take fn map<U, F: take fn(take T): U>(f: take F): Bound<U> {
        match take self {
            Bound.Included(value) => Bound.Included(f(value)),
            Bound.Excluded(value) => Bound.Excluded(f(value)),
            Bound.Unbounded => Bound.Unbounded
        }
    }
}
extend<T: Clone> Bound<T> implements Clone {
    fn clone(): Bound<T> {
        match self {
            Bound.Included(value) => Bound.Included(value.clone()),
            Bound.Excluded(value) => Bound.Excluded(value.clone()),
            Bound.Unbounded => Bound.Unbounded
        }
    }
}

pub interface RangeBounds<T: unsized> {
    fn start_bound(): Bound<read T from self>;
    fn end_bound(): Bound<read T from self>;
    fn contains<U: unsized>(value: read U): bool where T: PartialOrd<U>, U: PartialOrd<T> {
        let after_start = match take self.start_bound() {
            Bound.Included(start) => start.le(read value),
            Bound.Excluded(start) => start.lt(read value),
            Bound.Unbounded => true
        }
        if !after_start { return false }
        match take self.end_bound() {
            Bound.Included(end) => end.ge(read value),
            Bound.Excluded(end) => end.gt(read value),
            Bound.Unbounded => true
        }
    }
}

extend<T> Range<T> implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { Bound.Included(read self.start) }
    fn end_bound(): Bound<read T from self> { Bound.Excluded(read self.end) }
}
extend<T> RangeInclusive<T> implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> {
        if self.done { Bound.Excluded(read self.end) } else { Bound.Included(read self.start) }
    }
    fn end_bound(): Bound<read T from self> {
        if self.done { Bound.Excluded(read self.end) } else { Bound.Included(read self.end) }
    }
}
extend<T> RangeFrom<T> implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { Bound.Included(read self.start) }
    fn end_bound(): Bound<read T from self> { Bound.Unbounded }
}
extend<T> RangeTo<T> implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { Bound.Unbounded }
    fn end_bound(): Bound<read T from self> { Bound.Excluded(read self.end) }
}
extend<T> RangeToInclusive<T> implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { Bound.Unbounded }
    fn end_bound(): Bound<read T from self> { Bound.Included(read self.end) }
}
extend<T: unsized> RangeFull implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { Bound.Unbounded }
    fn end_bound(): Bound<read T from self> { Bound.Unbounded }
}
extend<T> (Bound<T>, Bound<T>) implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { self.0.as_ref() }
    fn end_bound(): Bound<read T from self> { self.1.as_ref() }
}
extend<region r, T: unsized, R: RangeBounds<T> + unsized> read R from r implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { R.(RangeBounds<T>).start_bound(read *self) }
    fn end_bound(): Bound<read T from self> { R.(RangeBounds<T>).end_bound(read *self) }
}
extend<region r, T: unsized, R: RangeBounds<T> + unsized> mut R from r implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { R.(RangeBounds<T>).start_bound(read *self) }
    fn end_bound(): Bound<read T from self> { R.(RangeBounds<T>).end_bound(read *self) }
}

extend<region r, T: unsized> Range<read T from r> implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { Bound.Included(self.start) }
    fn end_bound(): Bound<read T from self> { Bound.Excluded(self.end) }
}
extend<region r, T: unsized> RangeInclusive<read T from r> implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> {
        if self.done { Bound.Excluded(self.end) } else { Bound.Included(self.start) }
    }
    fn end_bound(): Bound<read T from self> {
        if self.done { Bound.Excluded(self.end) } else { Bound.Included(self.end) }
    }
}
extend<region r, T: unsized> RangeFrom<read T from r> implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { Bound.Included(self.start) }
    fn end_bound(): Bound<read T from self> { Bound.Unbounded }
}
extend<region r, T: unsized> RangeTo<read T from r> implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { Bound.Unbounded }
    fn end_bound(): Bound<read T from self> { Bound.Excluded(self.end) }
}
extend<region r, T: unsized> RangeToInclusive<read T from r> implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> { Bound.Unbounded }
    fn end_bound(): Bound<read T from self> { Bound.Included(self.end) }
}
extend<region r, T: unsized> (Bound<read T from r>, Bound<read T from r>) implements RangeBounds<T> {
    fn start_bound(): Bound<read T from self> {
        match self.0 {
            Bound.Included(value) => Bound.Included(value),
            Bound.Excluded(value) => Bound.Excluded(value),
            Bound.Unbounded => Bound.Unbounded
        }
    }
    fn end_bound(): Bound<read T from self> {
        match self.1 {
            Bound.Included(value) => Bound.Included(value),
            Bound.Excluded(value) => Bound.Excluded(value),
            Bound.Unbounded => Bound.Unbounded
        }
    }
}

pub interface Step: Sized + Copy + Ord {
    fn successor(): Self?;
    fn predecessor(): Self?;
    fn steps_between(other: read Self): (usize, usize?) { (0usize, none) }
}

// The unbounded range stops after yielding the scalar maximum.
pub type RangeFrom<T> { start: T; done: bool }
extend<T: Clone> RangeFrom<T> implements Clone {
    fn clone(): RangeFrom<T> { RangeFrom(self.start.clone(), self.done) }
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
pub fn range_from<T: Copy>(start: T): RangeFrom<T> { RangeFrom(start, false) }

// The half-open range `[start, end)`.
pub type Range<T> { pub start: T; pub end: T }
extend<T: Clone> Range<T> implements Clone {
    fn clone(): Range<T> { Range(self.start.clone(), self.end.clone()) }
}
extend<T: Step> Range<T> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) {
        if self.start >= self.end { return (0usize, present(0usize)) }
        self.start.steps_between(read self.end)
    }
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
pub fn range<T: Copy>(start: T, end: T): Range<T> { Range(start, end) }

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
extend<T: Clone> RangeInclusive<T> implements Clone {
    fn clone(): RangeInclusive<T> { RangeInclusive(self.start.clone(), self.end.clone(), self.done) }
}
extend<T: Step> RangeInclusive<T> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) {
        if self.done || self.start > self.end { return (0usize, present(0usize)) }
        let bounds = self.start.steps_between(read self.end)
        let upper = match bounds.1 {
            present(count) => count.checked_add(1usize),
            none => none
        }
        (bounds.0.saturating_add(1usize), upper)
    }
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
pub fn range_inclusive<T: Copy>(start: T, end: T): RangeInclusive<T> { RangeInclusive(start, end, false) }

// Folding capabilities: `zero`/`one` are the identities of `plus`/`times`.
pub interface Sum<Input = Self>: Sized {
    static fn zero(): Self;
    fn plus(other: take Input): Self;
}
pub interface Product<Input = Self>: Sized {
    static fn one(): Self;
    fn times(other: take Input): Self;
}
pub fn sum<I: Iterator>(items: take I): I.Item where I.Item: Sum {
    items.sum<I.Item>()
}
pub fn product<I: Iterator>(items: take I): I.Item where I.Item: Product {
    items.product<I.Item>()
}

extend<B, I: ExactSizeIterator, F: mut fn(take I.(Iterator).Item): B> Mapped<B, I, F> implements ExactSizeIterator {}
extend<B, I: FusedIterator, F: mut fn(take I.(Iterator).Item): B> Mapped<B, I, F> implements FusedIterator {}
extend<I: FusedIterator, F: mut fn(read I.(Iterator).Item): bool> Filtered<I, F> implements FusedIterator {}
extend<B, I: FusedIterator, F: mut fn(take I.(Iterator).Item): B?> FilterMapped<B, I, F> implements FusedIterator {}
extend<region r, T: Clone, I: ExactSizeIterator + Iterator<Item = read T from r>> Cloned<region r, T, I> implements ExactSizeIterator {}
extend<region r, T: Clone, I: FusedIterator + Iterator<Item = read T from r>> Cloned<region r, T, I> implements FusedIterator {}
extend<region r, T: Copy, I: ExactSizeIterator + Iterator<Item = read T from r>> Copied<region r, T, I> implements ExactSizeIterator {}
extend<region r, T: Copy, I: FusedIterator + Iterator<Item = read T from r>> Copied<region r, T, I> implements FusedIterator {}
extend<I: ExactSizeIterator> Enumerated<I> implements ExactSizeIterator {}
extend<I: FusedIterator> Enumerated<I> implements FusedIterator {}
extend<A: ExactSizeIterator, B: ExactSizeIterator> Zipped<A, B> implements ExactSizeIterator {}
extend<A: FusedIterator, B: FusedIterator> Zipped<A, B> implements FusedIterator {}
extend<T, A: FusedIterator + Iterator<Item = T>, B: FusedIterator + Iterator<Item = T>> Chained<A, B> implements FusedIterator {}
extend<I: ExactSizeIterator> Limited<I> implements ExactSizeIterator {}
extend<I: FusedIterator> Limited<I> implements FusedIterator {}
extend<I: ExactSizeIterator> Skipped<I> implements ExactSizeIterator {}
extend<I: FusedIterator> Skipped<I> implements FusedIterator {}
extend<I: FusedIterator, F: mut fn(read I.(Iterator).Item): bool> TakenWhile<I, F> implements FusedIterator {}
extend<I: FusedIterator, F: mut fn(read I.(Iterator).Item): bool> SkippedWhile<I, F> implements FusedIterator {}
extend<I: ExactSizeIterator> Stepped<I> implements ExactSizeIterator {}
extend<I: FusedIterator> Stepped<I> implements FusedIterator {}
extend<I: ExactSizeIterator, F: mut fn(read I.(Iterator).Item): Unit> Inspected<I, F> implements ExactSizeIterator {}
extend<I: FusedIterator, F: mut fn(read I.(Iterator).Item): Unit> Inspected<I, F> implements FusedIterator {}
extend<I: ExactSizeIterator> Fused<I> implements ExactSizeIterator {}
extend<I: Iterator> Fused<I> implements FusedIterator {}
extend<I: Iterator + Clone> Cycled<I> implements FusedIterator {}
extend<I: ExactSizeIterator + BidirectionalIterator> Reversed<I> implements ExactSizeIterator {}
extend<I: FusedIterator + BidirectionalIterator> Reversed<I> implements FusedIterator {}
extend<I: ExactSizeIterator> Peekable<I> implements ExactSizeIterator {}
extend<I: FusedIterator> Peekable<I> implements FusedIterator {}
extend<T, F: mut fn(): T> RepeatWith<T, F> implements FusedIterator {}
extend<T: Clone> Repeated<T> implements FusedIterator {}
extend<T, F: mut fn(read T): T?> Successors<T, F> implements FusedIterator {}
extend<U: Iterator, O: FusedIterator + Iterator<Item = U>> Flatten<U, O> implements FusedIterator {}
extend<O: FusedIterator, U: Iterator, F: mut fn(take O.(Iterator).Item): U> FlatMapped<O, U, F> implements FusedIterator {}
extend Range<i8> implements ExactSizeIterator {}
extend Range<i16> implements ExactSizeIterator {}
extend Range<i32> implements ExactSizeIterator {}
extend Range<isize> implements ExactSizeIterator {}
extend Range<u8> implements ExactSizeIterator {}
extend Range<u16> implements ExactSizeIterator {}
extend Range<u32> implements ExactSizeIterator {}
extend Range<usize> implements ExactSizeIterator {}
extend<T: Step> Range<T> implements FusedIterator {}
extend RangeInclusive<i8> implements ExactSizeIterator {}
extend RangeInclusive<i16> implements ExactSizeIterator {}
extend RangeInclusive<u8> implements ExactSizeIterator {}
extend RangeInclusive<u16> implements ExactSizeIterator {}
extend<T: Step> RangeInclusive<T> implements FusedIterator {}
extend<T: Step> RangeFrom<T> implements FusedIterator {}

fn integer_steps_between(start: u128, end: u128, reversed: bool): (usize, usize?) {
    if reversed { return (0usize, present(0usize)) }
    let distance = end.wrapping_sub(start)
    if distance > (usize.MAX as u128) { return (usize.MAX, none) }
    let exact = distance as usize
    (exact, present(exact))
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
    fn steps_between(other: read i8): (usize, usize?) {
        integer_steps_between(self as u128, other as u128, self > other)
    }
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
    fn steps_between(other: read i16): (usize, usize?) {
        integer_steps_between(self as u128, other as u128, self > other)
    }
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
    fn steps_between(other: read i32): (usize, usize?) {
        integer_steps_between(self as u128, other as u128, self > other)
    }
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
    fn steps_between(other: read i64): (usize, usize?) {
        integer_steps_between(self as u128, other as u128, self > other)
    }
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
    fn steps_between(other: read i128): (usize, usize?) {
        integer_steps_between(self as u128, other as u128, self > other)
    }
}

extend isize implements Step {
    fn successor(): isize? { self.checked_add(1isize) }
    fn predecessor(): isize? { self.checked_sub(1isize) }
    fn steps_between(other: read isize): (usize, usize?) {
        integer_steps_between(self as u128, other as u128, self > other)
    }
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
    fn steps_between(other: read u8): (usize, usize?) {
        integer_steps_between(self as u128, other as u128, self > other)
    }
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
    fn steps_between(other: read u16): (usize, usize?) {
        integer_steps_between(self as u128, other as u128, self > other)
    }
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
    fn steps_between(other: read u32): (usize, usize?) {
        integer_steps_between(self as u128, other as u128, self > other)
    }
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
    fn steps_between(other: read u64): (usize, usize?) {
        integer_steps_between(self as u128, other as u128, self > other)
    }
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
    fn steps_between(other: read u128): (usize, usize?) {
        integer_steps_between(self, other, self > other)
    }
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
    fn steps_between(other: read usize): (usize, usize?) {
        integer_steps_between(self as u128, other as u128, self > other)
    }
}

extend char implements Step {
    fn steps_between(other: read char): (usize, usize?) {
        if self > other { return (0usize, present(0usize)) }
        let start = self as u32
        let end = other as u32
        let gap = if start <= 0xd7ffu32 && end >= 0xe000u32 { 0x800u32 } else { 0u32 }
        let count = (end - start - gap) as usize
        (count, present(count))
    }
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

// Cloning preserves iterator position, buffered items and callable state.
extend<B, I: Clone, F: Clone> Mapped<B, I, F> implements Clone {
    fn clone(): Mapped<B, I, F> { Mapped(self.iter.clone(), self.f.clone(), Phantom<B>()) }
}
extend<I: Clone, F: Clone> Filtered<I, F> implements Clone {
    fn clone(): Filtered<I, F> { Filtered(self.iter.clone(), self.test.clone()) }
}
extend<B, I: Clone, F: Clone> FilterMapped<B, I, F> implements Clone {
    fn clone(): FilterMapped<B, I, F> { FilterMapped(self.iter.clone(), self.f.clone(), Phantom<B>()) }
}
extend<B, I: Clone, F: Clone> MappedWhile<B, I, F> implements Clone {
    fn clone(): MappedWhile<B, I, F> { MappedWhile(self.iter.clone(), self.f.clone(), Phantom<B>()) }
}
extend<O: Clone, U: Clone, F: Clone> FlatMapped<O, U, F> implements Clone {
    fn clone(): FlatMapped<O, U, F> {
        FlatMapped(self.outer.clone(), self.front.clone(), self.back.clone(), self.outer_done, self.f.clone())
    }
}
extend<U: Iterator + Clone, O: Iterator<Item = U> + Clone> Flatten<U, O> implements Clone {
    fn clone(): Flatten<U, O> {
        Flatten(self.outer.clone(), self.front.clone(), self.back.clone(), self.outer_done)
    }
}
extend<region r, T, I: Clone> Cloned<region r, T, I> implements Clone {
    fn clone(): Cloned<region r, T, I> { Cloned(self.iter.clone(), Phantom<T>()) }
}
extend<region r, T, I: Clone> Copied<region r, T, I> implements Clone {
    fn clone(): Copied<region r, T, I> { Copied(self.iter.clone(), Phantom<T>()) }
}
extend<I: Clone, F: Clone> TakenWhile<I, F> implements Clone {
    fn clone(): TakenWhile<I, F> { TakenWhile(self.iter.clone(), self.test.clone(), self.done) }
}
extend<I: Clone, F: Clone> SkippedWhile<I, F> implements Clone {
    fn clone(): SkippedWhile<I, F> { SkippedWhile(self.iter.clone(), self.test.clone(), self.started) }
}
extend<I: Clone, F: Clone> Inspected<I, F> implements Clone {
    fn clone(): Inspected<I, F> { Inspected(self.iter.clone(), self.f.clone()) }
}
extend<I: Clone> Cycled<I> implements Clone {
    fn clone(): Cycled<I> { Cycled(self.original.clone(), self.iter.clone(), self.yielded, self.done) }
}

extend<I: Iterator + Clone> Enumerated<I> implements Clone {
    fn clone(): Enumerated<I> { Enumerated(self.iter.clone(), self.index) }
}
extend<I: Iterator + Clone> Limited<I> implements Clone {
    fn clone(): Limited<I> { Limited(self.iter.clone(), self.remaining) }
}
extend<I: Iterator + Clone> Skipped<I> implements Clone {
    fn clone(): Skipped<I> { Skipped(self.iter.clone(), self.pending) }
}
extend<I: Iterator + Clone> Stepped<I> implements Clone {
    fn clone(): Stepped<I> { Stepped(self.iter.clone(), self.step, self.first) }
}
extend<I: Iterator + Clone> Fused<I> implements Clone {
    fn clone(): Fused<I> { Fused(self.iter.clone(), self.done) }
}
extend<I: Iterator + Clone> Reversed<I> implements Clone {
    fn clone(): Reversed<I> { Reversed(self.iter.clone()) }
}
extend<A: Iterator + Clone, B: Iterator + Clone> Zipped<A, B> implements Clone {
    fn clone(): Zipped<A, B> { Zipped(self.first.clone(), self.second.clone()) }
}
extend<A: Iterator + Clone, B: Iterator + Clone> Chained<A, B> implements Clone {
    fn clone(): Chained<A, B> {
        let second = match self.second {
            present(rest) => present(rest.clone()),
            none => none
        }
        Chained(self.first.clone(), second, self.first_live)
    }
}

extend<I: Iterator + Default> Enumerated<I> implements Default {
    static fn default(): Enumerated<I> { Enumerated(I.(Default).default(), 0usize) }
}
extend<I: Iterator + Default> Limited<I> implements Default {
    static fn default(): Limited<I> { Limited(I.(Default).default(), 0usize) }
}
extend<I: Iterator + Default> Skipped<I> implements Default {
    static fn default(): Skipped<I> { Skipped(I.(Default).default(), 0usize) }
}
extend<I: Iterator + Default> Fused<I> implements Default {
    static fn default(): Fused<I> { Fused(I.(Default).default(), false) }
}
extend<I: Iterator + Default> Reversed<I> implements Default {
    static fn default(): Reversed<I> { Reversed(I.(Default).default()) }
}
extend<I: Iterator + Default> Peekable<I> implements Default {
    static fn default(): Peekable<I> { Peekable(I.(Default).default(), none, false) }
}
extend<A: Iterator + Default, B: Iterator + Default> Zipped<A, B> implements Default {
    static fn default(): Zipped<A, B> { Zipped(A.(Default).default(), B.(Default).default()) }
}
extend<T, A: Iterator<Item = T> + Default, B: Iterator<Item = T> + Default> Chained<A, B> implements Default {
    static fn default(): Chained<A, B> { Chained(A.(Default).default(), present(B.(Default).default()), true) }
}
