// Value conversion protocols. Fallible conversions carry their ordinary
// failure value in Mettle's native success/failure outcome.

pub interface From<T>: Sized {
    static fn from(take value: T): Self;
}

pub interface Into<T>: Sized {
    take fn into(): T;
}

pub interface TryFrom<T>: Sized {
    type Error;
    static fn try_from(take value: T): (Outcome<Self, Self.Error>);
}

pub interface TryInto<T>: Sized {
    type Error;
    take fn try_into(): (Outcome<T, Self.Error>);
}

pub const fn identity<T>(take value: T): T { value }

extend<T> T implements From<T> {
    static fn from(take value: T): T { value }
}
extend<T> T? implements From<T> {
    static fn from(take value: T): T? { present(value) }
}

extend<region r, T> (read T from r)? implements From<read (T?) from r> {
    static fn from(take value: read (T?) from r): (read T from r)? {
        value.as_view()
    }
}

extend<region r, T> (mut T from r)? implements From<mut (T?) from r> {
    static fn from(take value: mut (T?) from r): (mut T from r)? {
        match mut *value {
            present(item) => present(mut item),
            none => none
        }
    }
}

extend<T, U> T implements Into<U> where U: From<T> {
    take fn into(): U { U.(From<T>).from(self) }
}

extend<T, U> T implements TryFrom<U> where U: Into<T> {
    type Error = Never
    static fn try_from(take value: U): (Outcome<T, Never>) {
        success(value.into())
    }
}

extend<T, U> T implements TryInto<U> where U: TryFrom<T> {
    type Error = U.(TryFrom<T>).Error
    take fn try_into(): (Outcome<U, U.(TryFrom<T>).Error>) {
        U.(TryFrom<T>).try_from(self)
    }
}
