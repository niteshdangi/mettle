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
    pub fn then_present<T>(take value: T): T? {
        if self { present(value) } else { none }
    }
}

extend<T> T? {
    pub fn is_present(): bool { match self { present(value) => true, none => false } }
    pub fn is_none(): bool { match self { present(value) => false, none => true } }

    pub fn as_view(): (read T from self)? {
        match self { present(value) => present(read value), none => none }
    }
    pub mut fn as_mut(): (mut T from self)? {
        match mut self { present(value) => present(mut value), none => none }
    }
    pub mut fn get_or_insert(take value: T): mut T from self {
        if self.is_none() { let _ = self.replace(value) }
        match mut self {
            present(current) => mut current,
            none => super.panic.panic("get_or_insert failed to install a value")
        }
    }
    pub mut fn get_or_insert_with<F: take fn(): T>(take make: F): mut T from self {
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
    pub take fn expect(read message: Text): T {
        match take self { present(value) => value, none => super.panic.panic(message) }
    }
    pub unsafe fn unwrap_unchecked(receiver take self: T?): T { self.unwrap() }
    pub take fn unwrap_or(take fallback: T): T {
        match take self { present(value) => value, none => fallback }
    }
    pub take fn unwrap_or_else<F: take fn(): T>(take fallback: F): T {
        match take self { present(value) => value, none => fallback() }
    }

    pub take fn map<U, F: take fn(take T): U>(take f: F): U? {
        match take self { present(value) => present(f(value)), none => none }
    }
    pub take fn map_or<U, F: take fn(take T): U>(take fallback: U, take f: F): U {
        match take self { present(value) => f(value), none => fallback }
    }
    pub take fn map_or_else<U, F: take fn(): U, G: take fn(take T): U>(take fallback: F, take f: G): U {
        match take self { present(value) => f(value), none => fallback() }
    }
    pub take fn map_or_default<U: Default, F: take fn(take T): U>(take f: F): U {
        match take self { present(value) => f(value), none => U.(Default).default() }
    }
    pub take fn unwrap_or_default(): T where T: Default {
        match take self {
            present(value) => value,
            none => T.(Default).default()
        }
    }
    pub take fn is_present_and<F: take fn(take T): bool>(take test: F): bool {
        match take self { present(value) => test(value), none => false }
    }
    pub take fn is_none_or<F: take fn(take T): bool>(take test: F): bool {
        match take self { present(value) => test(value), none => true }
    }
    pub take fn and_then<U, F: take fn(take T): U?>(take f: F): U? {
        match take self { present(value) => f(value), none => none }
    }
    pub take fn and<U>(take other: U?): U? {
        match take self { present(_) => other, none => none }
    }
    pub take fn xor(take other: T?): T? {
        match take self {
            present(value) => match take other {
                present(_) => none,
                none => present(value)
            },
            none => other
        }
    }
    pub take fn or_else<F: take fn(): T?>(take f: F): T? {
        match take self { present(value) => present(value), none => f() }
    }
    pub take fn or(take other: T?): T? {
        match take self { present(value) => present(value), none => other }
    }
    pub take fn filter<F: take fn(read T): bool>(take keep: F): T? {
        match take self {
            present(value) => if keep(read value) { present(value) } else { none },
            none => none
        }
    }
    pub take fn inspect<F: take fn(read T): Unit>(take f: F): T? {
        match take self {
            present(value) => { f(read value); present(value) },
            none => none
        }
    }
    pub take fn ok_or<E>(take error: E): (Outcome<T, E>) {
        match take self { present(value) => success(value), none => failure(error) }
    }
    pub take fn ok_or_else<E, F: take fn(): E>(take error: F): (Outcome<T, E>) {
        match take self { present(value) => success(value), none => failure(error()) }
    }

    // Moves the payload out, leaving `none`.
    pub mut fn `take`(): T? {
        unsafe { core.ptr.replace(core.ptr.from_mut(self), none) }
    }
    pub mut fn take_value(): T? { self.`take`() }
    pub mut fn take_if<F: take fn(mut T): bool>(take test: F): T? {
        let should_take = match mut self {
            present(value) => test(mut value),
            none => false
        }
        if should_take { self.`take`() } else { none }
    }
    // Installs `value`, returning the previous contents.
    pub mut fn replace(take value: T): T? {
        unsafe { core.ptr.replace(core.ptr.from_mut(self), present(value)) }
    }
    // Installs `value`, dropping any previous payload, and returns a view of it.
    pub mut fn insert(take value: T): mut T from self {
        let _ = self.replace(value)
        match mut self {
            present(current) => mut current,
            none => super.panic.panic("insert failed to install a value")
        }
    }
    pub take fn zip<U>(take other: U?): (T, U)? {
        match take self {
            present(left) => match take other {
                present(right) => present((left, right)),
                none => none
            },
            none => none
        }
    }

    // A one-element view of a present payload, or an empty view. The empty
    // view's address is the optional itself, which is non-null and aligned for
    // `T`; no element is read through it.
    pub fn as_slice(): read [T] from self {
        match self {
            present(value) => unsafe { super.slice.from_raw_parts(core.ptr.from_ref(value), 1usize) },
            none => unsafe { super.slice.from_raw_parts(core.ptr.from_ref(self).cast<T>(), 0usize) }
        }
    }
    pub mut fn as_mut_slice(): mut [T] from self {
        let empty = core.ptr.from_mut(self).cast<T>()
        match mut self {
            present(value) => unsafe { super.slice.from_raw_parts_mut(core.ptr.from_mut(value), 1usize) },
            none => unsafe { super.slice.from_raw_parts_mut(empty, 0usize) }
        }
    }
    // Iterators over the zero or one payload: exact-size, fused and
    // double-ended, like slice iteration.
    pub fn iter(): super.slice.SliceIter<region self, T> { self.as_slice().iter() }
    pub mut fn iter_mut(): super.slice.SliceIterMut<region self, T> { self.as_mut_slice().iter_mut() }
}

extend<T> T? {
    pub fn as_pin_ref(receiver take self: pinned read Self): (pinned read T from self)? {
        match self.get_ref() {
            present(value) => {
                let payload: read T from self = read value
                // Safety: the payload remains at its address for the parent pin's loan.
                present(unsafe { core.pin.Pin.new_unchecked(payload) })
            },
            none => none
        }
    }
}

extend<T> T? {
    pub fn as_pin_mut(receiver mut self: pinned mut Self): (pinned mut T from self)? {
        match mut (unsafe { self.get_unchecked_mut() }) {
            present(value) => {
                let payload: mut T from self = mut value
                // Safety: the payload remains at its address for the parent pin's loan.
                present(unsafe { core.pin.Pin.new_unchecked(payload) })
            },
            none => none
        }
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

extend<T, E> (Outcome<T, E>)? {
    pub take fn transpose(): (Outcome<T?, E>) {
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
