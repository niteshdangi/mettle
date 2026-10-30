// Operations on the native optional `T?`. `import core::option;` makes the
// inherent methods below visible. Absence-panicking operations call
// `core::panic::panic`.

import super.text.Text;

extend<T> T? {
    pub fn is_present(): bool { match self { present(value) => true, none => false } }
    pub fn is_none(): bool { match self { present(value) => false, none => true } }

    pub fn as_view(): (read T from self)? {
        match self { present(value) => present(read value), none => none }
    }
    pub mut fn as_mut(): (mut T from self)? {
        match mut self { present(value) => present(mut value), none => none }
    }

    pub take fn unwrap(): T {
        match take self { present(value) => value, none => super.panic.panic("called `unwrap` on an absent value") }
    }
    pub take fn expect(message: read Text): T {
        match take self { present(value) => value, none => super.panic.panic(message) }
    }
    pub take fn unwrap_or(fallback: take T): T {
        match take self { present(value) => value, none => fallback }
    }
    pub take fn unwrap_or_else(fallback: fn(): T): T {
        match take self { present(value) => value, none => fallback() }
    }

    pub take fn map<U>(f: fn(take T): U): U? {
        match take self { present(value) => present(f(value)), none => none }
    }
    pub take fn map_or<U>(fallback: take U, f: fn(take T): U): U {
        match take self { present(value) => f(value), none => fallback }
    }
    pub take fn and_then<U>(f: fn(take T): U?): U? {
        match take self { present(value) => f(value), none => none }
    }
    pub take fn or_else(f: fn(): T?): T? {
        match take self { present(value) => present(value), none => f() }
    }
    pub take fn or(other: take T?): T? {
        match take self { present(value) => present(value), none => other }
    }
    pub take fn filter(keep: fn(read T): bool): T? {
        match take self {
            present(value) => if keep(read value) { present(value) } else { none },
            none => none
        }
    }
    pub take fn ok_or<E>(error: take E): (T throws E) {
        match take self { present(value) => success(value), none => failure(error) }
    }
    pub take fn ok_or_else<E>(error: fn(): E): (T throws E) {
        match take self { present(value) => success(value), none => failure(error()) }
    }

    // Moves the payload out, leaving `none`.
    pub mut fn take_value(): T? {
        unsafe { core.ptr.replace(core.ptr.from_mut(self), none) }
    }
    // Installs `value`, returning the previous contents.
    pub mut fn replace(value: take T): T? {
        unsafe { core.ptr.replace(core.ptr.from_mut(self), present(value)) }
    }
}
