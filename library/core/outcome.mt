// Operations on the native stored outcome `(T throws E)`.
// `import core.outcome;` makes the inherent methods below visible.

import super.text.Text
import super.default.Default
import super.clone.Clone
import super.ops.Deref
import super.ops.DerefMut

extend<T, E> (T throws E) {
    pub fn is_success(): bool { match self { success(value) => true, failure(error) => false } }
    pub fn is_failure(): bool { match self { success(value) => false, failure(error) => true } }
    pub fn as_view(): ((read T from self) throws (read E from self)) {
        match self {
            success(value) => success(read value),
            failure(error) => failure(read error)
        }
    }
    pub fn as_ref(): ((read T from self) throws (read E from self)) {
        match self {
            success(value) => success(read value),
            failure(error) => failure(read error)
        }
    }
    pub mut fn as_mut(): ((mut T from self) throws (mut E from self)) {
        match mut self {
            success(value) => success(mut value),
            failure(error) => failure(mut error)
        }
    }
    pub fn as_deref(): ((read T.(Deref).Target from self) throws (read E from self))
        where T: Deref {
        match self {
            success(value) => success(value.deref()),
            failure(error) => failure(read error)
        }
    }
    pub mut fn as_deref_mut(): ((mut T.(Deref).Target from self) throws (mut E from self))
        where T: DerefMut {
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
    pub take fn expect(message: read Text): T {
        match take self { success(value) => value, failure(error) => super.panic.panic(message) }
    }
    pub unsafe fn unwrap_unchecked(receiver self: take (T throws E)): T { self.unwrap() }
    pub take fn unwrap_err(): E {
        match take self {
            success(value) => super.panic.panic("called `unwrap_err` on a successful outcome"),
            failure(error) => error
        }
    }
    pub take fn expect_err(message: read Text): E {
        match take self {
            success(value) => super.panic.panic(message),
            failure(error) => error
        }
    }
    pub unsafe fn unwrap_err_unchecked(receiver self: take (T throws E)): E { self.unwrap_err() }
    pub take fn unwrap_failure(): E {
        match take self { success(value) => super.panic.panic("called `unwrap_failure` on a successful outcome"), failure(error) => error }
    }
    pub take fn unwrap_or(fallback: take T): T {
        match take self { success(value) => value, failure(error) => fallback }
    }
    pub take fn unwrap_or_else(fallback: fn(take E): T): T {
        match take self { success(value) => value, failure(error) => fallback(error) }
    }

    pub take fn map<U>(f: fn(take T): U): (U throws E) {
        match take self { success(value) => success(f(value)), failure(error) => failure(error) }
    }
    pub take fn map_or<U>(fallback: take U, f: fn(take T): U): U {
        match take self { success(value) => f(value), failure(error) => fallback }
    }
    pub take fn map_err<F>(f: fn(take E): F): (T throws F) {
        match take self { success(value) => success(value), failure(error) => failure(f(error)) }
    }
    pub take fn and<U>(other: take (U throws E)): (U throws E) {
        match take self { success(_) => other, failure(error) => failure(error) }
    }
    pub take fn map_or_else<U>(fallback: fn(take E): U, f: fn(take T): U): U {
        match take self { success(value) => f(value), failure(error) => fallback(error) }
    }
    pub take fn map_or_default<U: Default>(f: fn(take T): U): U {
        match take self { success(value) => f(value), failure(_) => U.(Default).default() }
    }
    pub take fn is_ok_and(test: fn(take T): bool): bool {
        match take self { success(value) => test(value), failure(error) => false }
    }
    pub take fn is_err_and(test: fn(take E): bool): bool {
        match take self { success(value) => false, failure(error) => test(error) }
    }
    pub take fn inspect(f: fn(read T): Unit): (T throws E) {
        match take self {
            success(value) => { f(read value); success(value) },
            failure(error) => failure(error)
        }
    }
    pub take fn inspect_err(f: fn(read E): Unit): (T throws E) {
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
    pub take fn expect_failure(message: read Text): E {
        match take self {
            success(value) => super.panic.panic(message),
            failure(error) => error
        }
    }
    pub take fn and_then<U>(f: fn(take T): (U throws E)): (U throws E) {
        match take self { success(value) => f(value), failure(error) => failure(error) }
    }
    pub take fn or_else<F>(f: fn(take E): (T throws F)): (T throws F) {
        match take self { success(value) => success(value), failure(error) => f(error) }
    }
}

extend<region r, T: Clone, E: Clone> ((read T from r) throws (read E from r)) {
    pub take fn cloned(): (T throws E) {
        match take self {
            success(value) => success(value.clone()),
            failure(error) => failure(error.clone())
        }
    }
}

extend<region r, T: Copy, E: Copy> ((read T from r) throws (read E from r)) {
    pub take fn copied(): (T throws E) {
        match take self {
            success(value) => success(*value),
            failure(error) => failure(*error)
        }
    }
}

extend<T, E> ((T throws E) throws E) {
    pub take fn flatten(): (T throws E) {
        match take self {
            success(inner) => inner,
            failure(error) => failure(error)
        }
    }
}

extend<T, E> (T? throws E) {
    pub take fn transpose(): (T throws E)? {
        match take self {
            success(value) => match take value {
                present(item) => present(success(item)),
                none => none
            },
            failure(error) => present(failure(error))
        }
    }
}
