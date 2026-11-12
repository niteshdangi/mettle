import super.clone.ArrayInit
import super.clone.Clone
import super.convert.{From, TryFrom}
import super.error.{Error as CoreError}
import super.fmt.{Debug, Display, Error, Formatter}
import super.iter.OwnedIterable

pub fn from_fn<T, const N: usize, F: mut fn(usize): T>(take f: F): [T; N] {
    var result = ArrayInit<T, N>.new()
    var index = 0usize
    while index < N {
        result.push(f(index))
        index += 1usize
    }
    result.finish()
}

extend<T, const N: usize> [T; N] {
    pub take fn map<U, F: mut fn(take T): U>(take f: F): [U; N] {
        var result = ArrayInit<U, N>.new()
        for value in take self { result.push(f(value)) }
        result.finish()
    }
}

pub copy type TryFromSliceError {}
extend TryFromSliceError implements Clone {
    fn clone(): TryFromSliceError { self }
}
extend TryFromSliceError implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("TryFromSliceError(())") }
}
extend TryFromSliceError implements Display {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("slice length does not match array length") }
}
extend TryFromSliceError implements CoreError {}

extend<region r, T, const N: usize> read [T; N] from r implements TryFrom<read [T] from r> {
    type Error = TryFromSliceError
    static fn try_from(take value: read [T] from r): (Outcome<read [T; N] from r, TryFromSliceError>) {
        match value.as_array<N>() {
            present(array) => success(array),
            none => failure(TryFromSliceError())
        }
    }
}

extend<region r, T, const N: usize> mut [T; N] from r implements TryFrom<mut [T] from r> {
    type Error = TryFromSliceError
    static fn try_from(take value: mut [T] from r): (Outcome<mut [T; N] from r, TryFromSliceError>) {
        match take value.as_mut_array<N>() {
            present(array) => success(take array),
            none => failure(TryFromSliceError())
        }
    }
}

extend<region r, T: Copy, const N: usize> [T; N] implements TryFrom<read [T] from r> {
    type Error = TryFromSliceError
    static fn try_from(take value: read [T] from r): (Outcome<[T; N], TryFromSliceError>) {
        match value.as_array<N>() {
            present(array) => success(*array),
            none => failure(TryFromSliceError())
        }
    }
}

extend<region r, T: Copy, const N: usize> [T; N] implements TryFrom<mut [T] from r> {
    type Error = TryFromSliceError
    static fn try_from(take value: mut [T] from r): (Outcome<[T; N], TryFromSliceError>) {
        match value.as_array<N>() {
            present(array) => success(*array),
            none => failure(TryFromSliceError())
        }
    }
}

extend<T, const N: usize> [core.mem.MaybeUninit<T>; N]
    implements From<core.mem.MaybeUninit<[T; N]>> {
    static fn from(take value: core.mem.MaybeUninit<[T; N]>): [core.mem.MaybeUninit<T>; N] {
        // MaybeUninit preserves element layout without requiring initialized payloads.
        unsafe { core.mem.transmute<[core.mem.MaybeUninit<T>; N]>(value) }
    }
}

macro tuple_array_conversion {
    ($count:literal; $($element:ty => $field:literal => $name:ident),*) => {
        extend<T> [T; $count] implements From<($($element,)*)> {
            static fn from(take value: ($($element,)*)): [T; $count] {
                [$(value.$field,)*]
            }
        }
        extend<T> ($($element,)*) implements From<[T; $count]> {
            static fn from(take value: [T; $count]): ($($element,)*) {
                let [$($name,)*] = value
                ($($name,)*)
            }
        }
    };
}

tuple_array_conversion!(1; T => 0 => a)
tuple_array_conversion!(2; T => 0 => a, T => 1 => b)
tuple_array_conversion!(3; T => 0 => a, T => 1 => b, T => 2 => c)
tuple_array_conversion!(4; T => 0 => a, T => 1 => b, T => 2 => c, T => 3 => d)
tuple_array_conversion!(5; T => 0 => a, T => 1 => b, T => 2 => c, T => 3 => d, T => 4 => e)
tuple_array_conversion!(6; T => 0 => a, T => 1 => b, T => 2 => c, T => 3 => d, T => 4 => e, T => 5 => f)
tuple_array_conversion!(7; T => 0 => a, T => 1 => b, T => 2 => c, T => 3 => d, T => 4 => e, T => 5 => f, T => 6 => g)
tuple_array_conversion!(8; T => 0 => a, T => 1 => b, T => 2 => c, T => 3 => d, T => 4 => e, T => 5 => f, T => 6 => g, T => 7 => h)
tuple_array_conversion!(9; T => 0 => a, T => 1 => b, T => 2 => c, T => 3 => d, T => 4 => e, T => 5 => f, T => 6 => g, T => 7 => h, T => 8 => i)
tuple_array_conversion!(10; T => 0 => a, T => 1 => b, T => 2 => c, T => 3 => d, T => 4 => e, T => 5 => f, T => 6 => g, T => 7 => h, T => 8 => i, T => 9 => j)
tuple_array_conversion!(11; T => 0 => a, T => 1 => b, T => 2 => c, T => 3 => d, T => 4 => e, T => 5 => f, T => 6 => g, T => 7 => h, T => 8 => i, T => 9 => j, T => 10 => k)
tuple_array_conversion!(12; T => 0 => a, T => 1 => b, T => 2 => c, T => 3 => d, T => 4 => e, T => 5 => f, T => 6 => g, T => 7 => h, T => 8 => i, T => 9 => j, T => 10 => k, T => 11 => l)
