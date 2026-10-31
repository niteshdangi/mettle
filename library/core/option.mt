// Operations on the native optional `T?`. `import core.option;` makes the
// inherent methods below visible. Absence-panicking operations call
// `core.panic.panic`.

import super.text.Text
import super.default.Default
import super.clone.Clone
import super.ops.Deref
import super.ops.DerefMut

extend bool {
    // The value is evaluated before this method is called, whether or not it
    // is retained.
    pub fn then_some<T>(value: take T): T? {
        if self { present(value) } else { none }
    }
}

extend<T> T? {
    pub fn is_present(): bool { match self { present(value) => true, none => false } }
    pub fn is_none(): bool { match self { present(value) => false, none => true } }

    pub fn as_view(): (read T from self)? {
        match self { present(value) => present(read value), none => none }
    }
    pub fn as_ref(): (read T from self)? {
        match self { present(value) => present(read value), none => none }
    }

    pub mut fn as_mut(): (mut T from self)? {
        match mut self { present(value) => present(mut value), none => none }
    }
    pub mut fn get_or_insert(value: take T): mut T from self {
        if self.is_none() { let _ = self.replace(value) }
        match mut self {
            present(current) => mut current,
            none => super.panic.panic("get_or_insert failed to install a value")
        }
    }
    pub mut fn get_or_insert_with(make: take fn(): T): mut T from self {
        if self.is_none() { let _ = self.replace(make()) }
        match mut self {
            present(current) => mut current,
            none => super.panic.panic("get_or_insert_with failed to install a value")
        }
    }
    pub mut fn get_or_insert_default(): mut T from self where T: Default {
        if self.is_none() { let _ = self.replace(T.(Default).default()) }
        match mut self {
            present(current) => mut current,
            none => super.panic.panic("get_or_insert_default failed to install a value")
        }
    }

    pub take fn unwrap(): T {
        match take self { present(value) => value, none => super.panic.panic("called `unwrap` on an absent value") }
    }
    pub take fn expect(message: read Text): T {
        match take self { present(value) => value, none => super.panic.panic(message) }
    }
    pub unsafe fn unwrap_unchecked(receiver self: take T?): T { self.unwrap() }
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
    pub take fn map_or_else<U>(fallback: fn(): U, f: fn(take T): U): U {
        match take self { present(value) => f(value), none => fallback() }
    }
    pub take fn map_or_default<U: Default>(f: fn(take T): U): U {
        match take self { present(value) => f(value), none => U.(Default).default() }
    }
    pub take fn unwrap_or_default(): T where T: Default {
        match take self {
            present(value) => value,
            none => T.(Default).default()
        }
    }
    pub take fn is_some_and(test: fn(take T): bool): bool {
        match take self { present(value) => test(value), none => false }
    }
    pub take fn is_none_or(test: fn(take T): bool): bool {
        match take self { present(value) => test(value), none => true }
    }
    pub take fn and_then<U>(f: fn(take T): U?): U? {
        match take self { present(value) => f(value), none => none }
    }
    pub take fn and<U>(other: take U?): U? {
        match take self { present(_) => other, none => none }
    }
    pub take fn xor(other: take T?): T? {
        match take self {
            present(value) => match take other {
                present(_) => none,
                none => present(value)
            },
            none => other
        }
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
        pub take fn inspect(f: fn(read T): Unit): T? {
            match take self {
                present(value) => { f(read value); present(value) },
                none => none
            }
        }
    }
    pub take fn ok_or<E>(error: take E): (T throws E) {
        match take self { present(value) => success(value), none => failure(error) }
    }
    pub take fn ok_or_else<E>(error: fn(): E): (T throws E) {
        match take self { present(value) => success(value), none => failure(error()) }
    }

    // Moves the payload out, leaving `none`.
    pub mut fn `take`(): T? {
        unsafe { core.ptr.replace(core.ptr.from_mut(self), none) }
    }
    pub mut fn take_value(): T? { self.`take`() }
    pub mut fn take_if(test: take fn(mut T): bool): T? {
        let should_take = match mut self {
            present(value) => test(mut value),
            none => false
        }
        if should_take { self.`take`() } else { none }
    }
    // Installs `value`, returning the previous contents.
    pub mut fn replace(value: take T): T? {
        unsafe { core.ptr.replace(core.ptr.from_mut(self), present(value)) }
    }
}

extend<T: Deref> T? {
    pub fn as_deref(): (read T.(Deref).Target from self)? {
        match self { present(value) => present(value.deref()), none => none }
    }
}

extend<T: DerefMut> T? {
    pub mut fn as_deref_mut(): (mut T.(Deref).Target from self)? {
        match mut self { present(value) => present(value.deref_mut()), none => none }
    }
}

extend<region r, T: Clone> (read T from r)? {
    pub take fn cloned(): T? {
        match take self { present(value) => present(value.clone()), none => none }
    }
}

extend<region r, T: Copy> (read T from r)? {
    pub take fn copied(): T? {
        match take self { present(value) => present(*value), none => none }
    }
}

extend<T> (T?)? {
    pub take fn flatten(): T? {
        match take self { present(value) => value, none => none }
    }
}

extend<T, E> (T throws E)? {
    pub take fn transpose(): (T? throws E) {
        match take self {
            present(result) => match take result {
                success(value) => success(present(value)),
                failure(error) => failure(error)
            },
            none => success(none)
        }
    }
}

extend<A, B> (A, B)? {
    pub take fn unzip(): (A?, B?) {
        match take self {
            present((left, right)) => (present(left), present(right)),
            none => (none, none)
        }
    }
}
