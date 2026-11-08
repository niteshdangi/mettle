// Value conversion protocols. Fallible conversions carry their ordinary
// failure value in Mettle's native success/failure outcome.

pub interface From<T>: Sized {
    static fn `from`(value: take T): Self;
}

pub interface Into<T>: Sized {
    take fn into(): T;
}

pub interface TryFrom<T>: Sized {
    type Error;
    static fn try_from(value: take T): (Self throws Self.Error);
}

pub interface TryInto<T>: Sized {
    type Error;
    take fn try_into(): (T throws Self.Error);
}

extend<T> T implements From<T> {
    static fn `from`(value: take T): T { value }
}

extend<T, U> T implements Into<U> where U: From<T> {
    take fn into(): U { U.(From<T>).`from`(self) }
}

// Rust's blanket `TryFrom<U> for T where U: Into<T>` needs coherence to rule
// out explicit fallible pairs whose `Into` is never implemented; until then the
// identity conversion is the blanket, and each lossless library pair declares
// its never-failing TryFrom beside its From.
extend<T> T implements TryFrom<T> {
    type Error = Never
    static fn try_from(value: take T): (T throws Never) { success(value) }
}

extend<T, U> T implements TryInto<U> where U: TryFrom<T> {
    type Error = U.(TryFrom<T>).Error
    take fn try_into(): (U throws U.(TryFrom<T>).Error) {
        U.(TryFrom<T>).try_from(self)
    }
}
