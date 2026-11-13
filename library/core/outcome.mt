// Operations on the native stored outcome `Outcome<T, E>`.
// `import core.outcome;` makes the inherent methods below visible.

import super.text.Text
import super.default.Default
import super.clone.Clone
import super.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import super.hash.{Hash, Hasher}
import super.ops.Deref
import super.ops.DerefMut

extend<T, E> (Outcome<T, E>) {
    pub fn is_success(): bool { match self { success(value) => true, failure(error) => false } }
    pub fn is_failure(): bool { match self { success(value) => false, failure(error) => true } }
    pub fn as_view(): (Outcome<(read T from self), (read E from self)>) {
        match self {
            success(value) => success(read value),
            failure(error) => failure(read error)
        }
    }
    pub mut fn as_mut(): (Outcome<(mut T from self), (mut E from self)>) {
        match mut self {
            success(value) => success(mut value),
            failure(error) => failure(mut error)
        }
    }
    pub fn as_deref(): (Outcome<(read T.(Deref).Target from self), (read E from self)>) where T: Deref {
        match self {
            success(value) => success(value.deref()),
            failure(error) => failure(read error)
        }
    }
    pub mut fn as_deref_mut(): (Outcome<(mut T.(Deref).Target from self), (mut E from self)>) where T: DerefMut {
        match mut self {
            success(value) => success(value.deref_mut()),
            failure(error) => failure(mut error)
        }
    }

    pub take fn ok(): T? {
        match take self { success(value) => present(value), failure(error) => none }
    }
    pub take fn err(): E? {
        match take self { success(value) => none, failure(error) => present(error) }
    }

    pub take fn unwrap(): T {
        match take self { success(value) => value, failure(error) => super.panic.panic("called `unwrap` on a failed outcome") }
    }
    pub take fn expect(read message: Text): T {
        match take self { success(value) => value, failure(error) => super.panic.panic(message) }
    }
    pub unsafe fn unwrap_unchecked(receiver take self: (Outcome<T, E>)): T { self.unwrap() }
    pub unsafe fn unwrap_err_unchecked(receiver take self: (Outcome<T, E>)): E { self.unwrap_failure() }
    pub take fn unwrap_failure(): E {
        match take self { success(value) => super.panic.panic("called `unwrap_failure` on a successful outcome"), failure(error) => error }
    }
    pub take fn unwrap_or(take fallback: T): T {
        match take self { success(value) => value, failure(error) => fallback }
    }
    pub take fn unwrap_or_else<F: take fn(take E): T>(take fallback: F): T {
        match take self { success(value) => value, failure(error) => fallback(error) }
    }

    pub take fn map<U, F: take fn(take T): U>(take f: F): (Outcome<U, E>) {
        match take self { success(value) => success(f(value)), failure(error) => failure(error) }
    }
    pub take fn map_or<U, F: take fn(take T): U>(take fallback: U, take f: F): U {
        match take self { success(value) => f(value), failure(error) => fallback }
    }
    pub take fn map_err<F, G: take fn(take E): F>(take f: G): (Outcome<T, F>) {
        match take self { success(value) => success(value), failure(error) => failure(f(error)) }
    }
    pub take fn and<U>(take other: (Outcome<U, E>)): (Outcome<U, E>) {
        match take self { success(_) => other, failure(error) => failure(error) }
    }
    pub take fn map_or_else<U, F: take fn(take E): U, G: take fn(take T): U>(take fallback: F, take f: G): U {
        match take self { success(value) => f(value), failure(error) => fallback(error) }
    }
    pub take fn map_or_default<U: Default, F: take fn(take T): U>(take f: F): U {
        match take self { success(value) => f(value), failure(_) => U.(Default).default() }
    }
    pub take fn is_success_and<F: take fn(take T): bool>(take test: F): bool {
        match take self { success(value) => test(value), failure(error) => false }
    }
    pub take fn is_failure_and<F: take fn(take E): bool>(take test: F): bool {
        match take self { success(value) => false, failure(error) => test(error) }
    }
    pub take fn inspect<F: take fn(read T): Unit>(take f: F): (Outcome<T, E>) {
        match take self {
            success(value) => { f(read value); success(value) },
            failure(error) => failure(error)
        }
    }
    pub take fn inspect_failure<F: take fn(read E): Unit>(take f: F): (Outcome<T, E>) {
        match take self {
            success(value) => success(value),
            failure(error) => { f(read error); failure(error) }
        }
    }
    pub take fn unwrap_or_default(): T where T: Default {
        match take self {
            success(value) => value,
            failure(error) => T.(Default).default()
        }
    }
    pub take fn expect_failure(read message: Text): E {
        match take self {
            success(value) => super.panic.panic(message),
            failure(error) => error
        }
    }
    pub take fn and_then<U, F: take fn(take T): (Outcome<U, E>)>(take f: F): (Outcome<U, E>) {
        match take self { success(value) => f(value), failure(error) => failure(error) }
    }
    pub take fn or_else<F, G: take fn(take E): (Outcome<T, F>)>(take f: G): (Outcome<T, F>) {
        match take self { success(value) => success(value), failure(error) => f(error) }
    }
    pub take fn or<F>(take other: (Outcome<T, F>)): (Outcome<T, F>) {
        match take self { success(value) => success(value), failure(error) => other }
    }

    // Iterators over the zero or one success payload: exact-size, fused and
    // double-ended, like slice iteration. A failure yields an empty view whose
    // address is the outcome itself, which is non-null and aligned for `T`; no
    // element is read through it.
    pub fn iter(): super.slice.SliceIter<region self, T> {
        let view: read [T] from self = match self {
            success(value) => unsafe { super.slice.from_raw_parts(core.ptr.from_ref(value), 1usize) },
            failure(error) => unsafe { super.slice.from_raw_parts(core.ptr.from_ref(self).cast<T>(), 0usize) }
        }
        view.iter()
    }
    pub mut fn iter_mut(): super.slice.SliceIterMut<region self, T> {
        let empty = core.ptr.from_mut(self).cast<T>()
        let view: mut [T] from self = match mut self {
            success(value) => unsafe { super.slice.from_raw_parts_mut(core.ptr.from_mut(value), 1usize) },
            failure(error) => unsafe { super.slice.from_raw_parts_mut(empty, 0usize) }
        }
        view.iter_mut()
    }
}

// copied/cloned duplicate the borrowed success value; the failure passes
// through unchanged.
extend<region r, T: Clone, E> (Outcome<(read T from r), E>) {
    pub take fn cloned(): (Outcome<T, E>) {
        match take self {
            success(value) => success(value.clone()),
            failure(error) => failure(error)
        }
    }
}

extend<region r, T: Copy, E> (Outcome<(read T from r), E>) {
    pub take fn copied(): (Outcome<T, E>) {
        match take self {
            success(value) => success(*value),
            failure(error) => failure(error)
        }
    }
}

extend<region r, T: Clone, E> (Outcome<(mut T from r), E>) {
    pub take fn cloned(): (Outcome<T, E>) {
        match take self {
            success(value) => success(value.clone()),
            failure(error) => failure(error)
        }
    }
}

extend<region r, T: Copy, E> (Outcome<(mut T from r), E>) {
    pub take fn copied(): (Outcome<T, E>) {
        match take self {
            success(value) => success(*value),
            failure(error) => failure(error)
        }
    }
}

extend<T, E> (Outcome<(Outcome<T, E>), E>) {
    pub take fn flatten(): (Outcome<T, E>) {
        match take self {
            success(inner) => inner,
            failure(error) => failure(error)
        }
    }
}

extend<T, E> (Outcome<T?, E>) {
    pub take fn transpose(): (Outcome<T, E>)? {
        match take self {
            success(value) => match take value {
                present(item) => present(success(item)),
                none => none
            },
            failure(error) => present(failure(error))
        }
    }
}

// Success orders before failure, as in Rust's variant order.
extend<T: PartialEq, E: PartialEq> (Outcome<T, E>) implements PartialEq {
    fn eq(read other: (Outcome<T, E>)): bool {
        match self {
            success(left) => match other { success(right) => left == right, failure(_) => false },
            failure(left) => match other { failure(right) => left == right, success(_) => false }
        }
    }
}
extend<T: Eq, E: Eq> (Outcome<T, E>) implements Eq {}
extend<T: PartialOrd, E: PartialOrd> (Outcome<T, E>) implements PartialOrd {
    fn partial_cmp(read other: (Outcome<T, E>)): Ordering? {
        match self {
            success(left) => match other {
                success(right) => left.partial_cmp(right),
                failure(_) => present(Ordering.Less)
            },
            failure(left) => match other {
                failure(right) => left.partial_cmp(right),
                success(_) => present(Ordering.Greater)
            }
        }
    }
}
extend<T: Ord, E: Ord> (Outcome<T, E>) implements Ord {
    fn cmp(read other: (Outcome<T, E>)): Ordering {
        match self {
            success(left) => match other {
                success(right) => left.cmp(right),
                failure(_) => Ordering.Less
            },
            failure(left) => match other {
                failure(right) => left.cmp(right),
                success(_) => Ordering.Greater
            }
        }
    }
}
extend<T: Hash, E: Hash> (Outcome<T, E>) implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        match self {
            success(value) => { state.write_u8(0u8); value.hash(mut state) },
            failure(error) => { state.write_u8(1u8); error.hash(mut state) }
        }
    }
}
