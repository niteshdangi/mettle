// Operations on the native stored outcome `(T throws E)`.
// `import core::outcome;` makes the inherent methods below visible.

import super.text.Text;

extend<T, E> (T throws E) {
    pub fn is_success(): bool { match self { success(value) => true, failure(error) => false } }
    pub fn is_failure(): bool { match self { success(value) => false, failure(error) => true } }

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
    pub take fn map_err<F>(f: fn(take E): F): (T throws F) {
        match take self { success(value) => success(value), failure(error) => failure(f(error)) }
    }
    pub take fn and_then<U>(f: fn(take T): (U throws E)): (U throws E) {
        match take self { success(value) => f(value), failure(error) => failure(error) }
    }
    pub take fn or_else<F>(f: fn(take E): (T throws F)): (T throws F) {
        match take self { success(value) => success(value), failure(error) => f(error) }
    }
}
