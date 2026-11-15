// Comparison capabilities. Operators dispatch to `PartialEq`/`PartialOrd` by
// these canonical paths; the primitive implementations below delegate to the
// compiler's built-in scalar comparisons.
import super.text.Text
import super.default.Default
import super.fmt.{ Debug, Formatter, Error }
import super.ops.ControlFlow
import super.clone.{Clone, FunctionPointer}

extend<F: FunctionPointer> F implements PartialEq {
    fn eq(read other: F): bool {
        core.intrinsics.fn_addr(self) == core.intrinsics.fn_addr(other)
    }
}
extend<F: FunctionPointer> F implements Eq {}
extend<F: FunctionPointer> F implements PartialOrd {
    fn partial_cmp(read other: F): Ordering? { present(self.cmp(other)) }
}
extend<F: FunctionPointer> F implements Ord {
    fn cmp(read other: F): Ordering {
        let left = core.intrinsics.fn_addr(self)
        let right = core.intrinsics.fn_addr(other)
        if left < right { Ordering.Less }
        else if left == right { Ordering.Equal }
        else { Ordering.Greater }
    }
}

@layout(i8)
pub copy enum Ordering { Less = -1; Equal = 0; Greater = 1 }

extend Ordering {
    pub fn is_lt(): bool { match self { Ordering.Less => true, Ordering.Equal => false, Ordering.Greater => false } }
    pub fn is_le(): bool { match self { Ordering.Greater => false, Ordering.Less => true, Ordering.Equal => true } }
    pub fn is_gt(): bool { match self { Ordering.Greater => true, Ordering.Equal => false, Ordering.Less => false } }
    pub fn is_ge(): bool { match self { Ordering.Less => false, Ordering.Equal => true, Ordering.Greater => true } }
    pub fn is_eq(): bool { match self { Ordering.Equal => true, Ordering.Less => false, Ordering.Greater => false } }
    pub fn is_ne(): bool { !self.is_eq() }
    pub fn reverse(): Ordering {
        match self { Ordering.Less => Ordering.Greater, Ordering.Equal => Ordering.Equal, Ordering.Greater => Ordering.Less }
    }
    // Lexicographic combination: `other` only decides when `self` is Equal.
    pub fn then(other: Ordering): Ordering {
        match self { Ordering.Equal => other, Ordering.Less => Ordering.Less, Ordering.Greater => Ordering.Greater }
    }
    pub fn then_with<F: take fn(): Ordering>(take other: F): Ordering {
        match self { Ordering.Equal => other(), Ordering.Less => Ordering.Less, Ordering.Greater => Ordering.Greater }
    }
}

pub interface PartialEq<Rhs: unsized = Self> {
    fn eq(read other: Rhs): bool;
    fn ne(read other: Rhs): bool { !self.eq(other) }
}

// Marker: `eq` is reflexive, symmetric and transitive.
pub interface Eq: PartialEq {}

pub interface PartialOrd<Rhs: unsized = Self>: PartialEq<Rhs> {
    fn partial_cmp(read other: Rhs): Ordering?;
    fn lt(read other: Rhs): bool {
        match self.partial_cmp(other) { present(o) => o.is_lt(), none => false }
    }
    fn le(read other: Rhs): bool {
        match self.partial_cmp(other) { present(o) => o.is_le(), none => false }
    }
    fn gt(read other: Rhs): bool {
        match self.partial_cmp(other) { present(o) => o.is_gt(), none => false }
    }
    fn ge(read other: Rhs): bool {
        match self.partial_cmp(other) { present(o) => o.is_ge(), none => false }
    }
}

// Total order consistent with `PartialOrd` and `Eq`.
pub interface Ord: Eq + PartialOrd {
    fn cmp(read other: Self): Ordering;
    // Equal values: `max` yields `other`, `min` yields `self`.
    take fn max(take other: Self): Self where Self: Sized { if other.cmp(read self).is_lt() { self } else { other } }
    take fn min(take other: Self): Self where Self: Sized { if other.cmp(read self).is_lt() { other } else { self } }
    take fn clamp(take low: Self, take high: Self): Self where Self: Sized {
        if low.cmp(read high).is_gt() { super.panic.panic("clamp requires low <= high") }
        if self.cmp(read low).is_lt() { low } else if high.cmp(read self).is_lt() { high } else { self }
    }
}

pub fn min<T: Ord>(take a: T, take b: T): T { if b.cmp(read a).is_lt() { b } else { a } }
pub fn max<T: Ord>(take a: T, take b: T): T { if b.cmp(read a).is_lt() { a } else { b } }
pub fn min_by<T, F: mut fn(read T, read T): Ordering>(
    take a: T,
    take b: T,
    take compare: F
): T {
    var comparator = compare
    if comparator(read a, read b).is_gt() { b } else { a }
}
pub fn max_by<T, F: mut fn(read T, read T): Ordering>(
    take a: T,
    take b: T,
    take compare: F
): T {
    var comparator = compare
    if comparator(read a, read b).is_gt() { a } else { b }
}
pub fn min_by_key<T, K: Ord, F: mut fn(read T): K>(
    take a: T,
    take b: T,
    take key: F
): T {
    var key_of = key
    let a_key = key_of(read a)
    let b_key = key_of(read b)
    if a_key.cmp(read b_key).is_gt() { b } else { a }
}
pub fn max_by_key<T, K: Ord, F: mut fn(read T): K>(
    take a: T,
    take b: T,
    take key: F
): T {
    var key_of = key
    let a_key = key_of(read a)
    let b_key = key_of(read b)
    if a_key.cmp(read b_key).is_gt() { a } else { b }
}
// Requires low <= high.
pub fn clamp<T: Ord>(take value: T, take low: T, take high: T): T {
    if low.cmp(read high).is_gt() { super.panic.panic("clamp requires low <= high") }
    if value.cmp(read low).is_lt() { low } else if high.cmp(read value).is_lt() { high } else { value }
}

// Inverts the order of the wrapped value.
pub copy type Descending<T> { pub value: T }
extend<T: PartialEq> Descending<T> implements PartialEq { fn eq(read other: Descending<T>): bool { other.value == self.value } }
extend<T: Eq> Descending<T> implements Eq {}
extend<T: super.clone.Clone> Descending<T> implements super.clone.Clone {
    fn clone(): Descending<T> { Descending(T.(Clone).clone(self.value)) }
}
extend<T: PartialOrd> Descending<T> implements PartialOrd {
    fn partial_cmp(read other: Descending<T>): Ordering? { other.value.partial_cmp(read self.value) }
}
extend<T: Ord> Descending<T> implements Ord { fn cmp(read other: Descending<T>): Ordering { other.value.cmp(read self.value) } }
extend<T: Default> Descending<T> implements Default {
    static fn default(): Descending<T> { Descending(T.(Default).default()) }
}
extend<T: Debug> Descending<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_tuple("Descending")
        try debug.field(read self.value)
        try debug.finish()
    }
}

extend Ordering implements PartialEq {
    fn eq(read other: Ordering): bool {
        match self {
            Ordering.Less => other.is_lt(),
            Ordering.Equal => other.is_eq(),
            Ordering.Greater => other.is_gt()
        }
    }
}
extend Ordering implements Eq {}

extend<B: PartialEq, C: PartialEq> ControlFlow<B, C> implements PartialEq {
    fn eq(read other: ControlFlow<B, C>): bool {
        match self {
            ControlFlow.Continue(value) => match other {
                ControlFlow.Continue(other_value) => value == other_value,
                ControlFlow.Break(_) => false
            },
            ControlFlow.Break(value) => match other {
                ControlFlow.Continue(_) => false,
                ControlFlow.Break(other_value) => value == other_value
            }
        }
    }
}
extend<B: Eq, C: Eq> ControlFlow<B, C> implements Eq {}

extend Never implements PartialEq {
    fn eq(read other: Never): bool { match self {} }
}
extend Never implements Eq {}
extend Never implements PartialOrd {
    fn partial_cmp(read other: Never): Ordering? { match self {} }
}
extend Never implements Ord {
    fn cmp(read other: Never): Ordering { match self {} }
}

extend i8 implements PartialEq { fn eq(read other: i8): bool { self == other } }
extend i8 implements Eq {}
extend i8 implements PartialOrd {
    fn partial_cmp(read other: i8): Ordering? { present(self.cmp(other)) }
}
extend i8 implements Ord {
    fn cmp(read other: i8): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend i16 implements PartialEq { fn eq(read other: i16): bool { self == other } }
extend i16 implements Eq {}
extend i16 implements PartialOrd {
    fn partial_cmp(read other: i16): Ordering? { present(self.cmp(other)) }
}
extend i16 implements Ord {
    fn cmp(read other: i16): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend i32 implements PartialEq { fn eq(read other: i32): bool { self == other } }
extend i32 implements Eq {}
extend i32 implements PartialOrd {
    fn partial_cmp(read other: i32): Ordering? { present(self.cmp(other)) }
}
extend i32 implements Ord {
    fn cmp(read other: i32): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend i64 implements PartialEq { fn eq(read other: i64): bool { self == other } }
extend i64 implements Eq {}
extend i64 implements PartialOrd {
    fn partial_cmp(read other: i64): Ordering? { present(self.cmp(other)) }
}
extend i64 implements Ord {
    fn cmp(read other: i64): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend i128 implements PartialEq { fn eq(read other: i128): bool { self == other } }
extend i128 implements Eq {}
extend i128 implements PartialOrd {
    fn partial_cmp(read other: i128): Ordering? { present(self.cmp(other)) }
}
extend i128 implements Ord {
    fn cmp(read other: i128): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend isize implements PartialEq { fn eq(read other: isize): bool { self == other } }
extend isize implements Eq {}
extend isize implements PartialOrd {
    fn partial_cmp(read other: isize): Ordering? { present(self.cmp(other)) }
}
extend isize implements Ord {
    fn cmp(read other: isize): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend u8 implements PartialEq { fn eq(read other: u8): bool { self == other } }
extend u8 implements Eq {}
extend u8 implements PartialOrd {
    fn partial_cmp(read other: u8): Ordering? { present(self.cmp(other)) }
}
extend u8 implements Ord {
    fn cmp(read other: u8): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend u16 implements PartialEq { fn eq(read other: u16): bool { self == other } }
extend u16 implements Eq {}
extend u16 implements PartialOrd {
    fn partial_cmp(read other: u16): Ordering? { present(self.cmp(other)) }
}
extend u16 implements Ord {
    fn cmp(read other: u16): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend u32 implements PartialEq { fn eq(read other: u32): bool { self == other } }
extend u32 implements Eq {}
extend u32 implements PartialOrd {
    fn partial_cmp(read other: u32): Ordering? { present(self.cmp(other)) }
}
extend u32 implements Ord {
    fn cmp(read other: u32): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend u64 implements PartialEq { fn eq(read other: u64): bool { self == other } }
extend u64 implements Eq {}
extend u64 implements PartialOrd {
    fn partial_cmp(read other: u64): Ordering? { present(self.cmp(other)) }
}
extend u64 implements Ord {
    fn cmp(read other: u64): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend u128 implements PartialEq { fn eq(read other: u128): bool { self == other } }
extend u128 implements Eq {}
extend u128 implements PartialOrd {
    fn partial_cmp(read other: u128): Ordering? { present(self.cmp(other)) }
}
extend u128 implements Ord {
    fn cmp(read other: u128): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend usize implements PartialEq { fn eq(read other: usize): bool { self == other } }
extend usize implements Eq {}
extend usize implements PartialOrd {
    fn partial_cmp(read other: usize): Ordering? { present(self.cmp(other)) }
}
extend usize implements Ord {
    fn cmp(read other: usize): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend f32 implements PartialEq { fn eq(read other: f32): bool { self == other } }
extend f32 implements PartialOrd {
    fn partial_cmp(read other: f32): Ordering? {
        if self < other { present(Ordering.Less) }
        else if self > other { present(Ordering.Greater) }
        else if self == other { present(Ordering.Equal) }
        else { none }
    }
}

extend f64 implements PartialEq { fn eq(read other: f64): bool { self == other } }
extend f64 implements PartialOrd {
    fn partial_cmp(read other: f64): Ordering? {
        if self < other { present(Ordering.Less) }
        else if self > other { present(Ordering.Greater) }
        else if self == other { present(Ordering.Equal) }
        else { none }
    }
}

extend char implements PartialEq { fn eq(read other: char): bool { self == other } }
extend char implements Eq {}
extend char implements PartialOrd {
    fn partial_cmp(read other: char): Ordering? { present(self.cmp(other)) }
}
extend char implements Ord {
    fn cmp(read other: char): Ordering {
        if self < other { Ordering.Less } else if self == other { Ordering.Equal } else { Ordering.Greater }
    }
}

extend bool implements PartialEq { fn eq(read other: bool): bool { (self as u8) == (other as u8) } }
extend bool implements Eq {}
extend bool implements PartialOrd {
    fn partial_cmp(read other: bool): Ordering? { present(self.cmp(other)) }
}
extend bool implements Ord {
    fn cmp(read other: bool): Ordering {
        if (self as u8) < (other as u8) { Ordering.Less } else if (self as u8) == (other as u8) { Ordering.Equal } else { Ordering.Greater }
    }
}

// The comma-terminated prefix and semicolon-separated final type make the
// possibly-unsized tail unambiguous while keeping one implementation pattern.
macro tuple_comparison {
    ($($prefix:ident => $other_prefix:ident => $prefix_field:literal,)* ; $last:ident => $other_last:ident => $last_field:literal) => {
        extend<
            $($prefix: PartialEq<$other_prefix>, $other_prefix,)*
            $last: PartialEq<$other_last> + unsized,
            $other_last: unsized
        > ($($prefix,)* $last,)
            implements PartialEq<($($other_prefix,)* $other_last,)> {
            fn eq(read other: ($($other_prefix,)* $other_last,)): bool {
        $(self.$prefix_field == other.$prefix_field &&)*
                self.$last_field == other.$last_field
            }
        }

        extend<$($prefix: Eq,)* $last: Eq + unsized> ($($prefix,)* $last,) implements Eq {}

        extend<
            $($prefix: PartialOrd<$other_prefix>, $other_prefix,)*
            $last: PartialOrd<$other_last> + unsized,
            $other_last: unsized
        > ($($prefix,)* $last,)
            implements PartialOrd<($($other_prefix,)* $other_last,)> {
            fn partial_cmp(read other: ($($other_prefix,)* $other_last,)): Ordering? {
                $(
                    match self.$prefix_field.partial_cmp(read other.$prefix_field) {
                        present(order) => if !order.is_eq() { return present(order) },
                        none => { return none }
                    };
                )*
                self.$last_field.partial_cmp(read other.$last_field)
            }
        }

        extend<$($prefix: Ord,)* $last: Ord + unsized> ($($prefix,)* $last,) implements Ord {
            fn cmp(read other: ($($prefix,)* $last,)): Ordering {
                $(
                    match self.$prefix_field.cmp(read other.$prefix_field) {
                        Ordering.Equal => {},
                        order => { return order }
                    };
                )*
                self.$last_field.cmp(read other.$last_field)
            }
        }
    };
}

tuple_comparison!(; A => A2 => 0)
tuple_comparison!(
    A => A2 => 0,
    ; B => B2 => 1
)
tuple_comparison!(
    A => A2 => 0, B => B2 => 1,
    ; C => C2 => 2
)
tuple_comparison!(
    A => A2 => 0, B => B2 => 1, C => C2 => 2,
    ; D => D2 => 3
)
tuple_comparison!(
    A => A2 => 0, B => B2 => 1, C => C2 => 2,
    D => D2 => 3,
    ; E => E2 => 4
)
tuple_comparison!(
    A => A2 => 0, B => B2 => 1, C => C2 => 2,
    D => D2 => 3, E => E2 => 4,
    ; F => F2 => 5
)
tuple_comparison!(
    A => A2 => 0, B => B2 => 1, C => C2 => 2,
    D => D2 => 3, E => E2 => 4, F => F2 => 5,
    ; G => G2 => 6
)
tuple_comparison!(
    A => A2 => 0, B => B2 => 1, C => C2 => 2,
    D => D2 => 3, E => E2 => 4, F => F2 => 5,
    G => G2 => 6,
    ; H => H2 => 7
)
tuple_comparison!(
    A => A2 => 0, B => B2 => 1, C => C2 => 2,
    D => D2 => 3, E => E2 => 4, F => F2 => 5,
    G => G2 => 6, H => H2 => 7,
    ; I => I2 => 8
)
tuple_comparison!(
    A => A2 => 0, B => B2 => 1, C => C2 => 2,
    D => D2 => 3, E => E2 => 4, F => F2 => 5,
    G => G2 => 6, H => H2 => 7, I => I2 => 8,
    ; J => J2 => 9
)
tuple_comparison!(
    A => A2 => 0, B => B2 => 1, C => C2 => 2,
    D => D2 => 3, E => E2 => 4, F => F2 => 5,
    G => G2 => 6, H => H2 => 7, I => I2 => 8,
    J => J2 => 9,
    ; K => K2 => 10
)
tuple_comparison!(
    A => A2 => 0, B => B2 => 1, C => C2 => 2,
    D => D2 => 3, E => E2 => 4, F => F2 => 5,
    G => G2 => 6, H => H2 => 7, I => I2 => 8,
    J => J2 => 9, K => K2 => 10,
    ; L => L2 => 11
)
extend<T: PartialEq<U>, U> [T] implements PartialEq<[U]> {
    fn eq(read other: [U]): bool {
        if self.len() != other.len() { return false }
        var i = 0usize
        while i < self.len() {
            if self[i] != other[i] { return false }
            i += 1usize
        }
        true
    }
}
extend<T: Eq> [T] implements Eq {}
extend<T: PartialOrd> [T] implements PartialOrd {
    fn partial_cmp(read other: [T]): Ordering? {
        var i = 0usize
        while i < self.len() && i < other.len() {
            match self[i].partial_cmp(read other[i]) {
                present(order) => if !order.is_eq() { return present(order) },
                none => { return none }
            }
            i += 1usize
        }
        present(self.len().cmp(other.len()))
    }
}
extend<T: Ord> [T] implements Ord {
    fn cmp(read other: [T]): Ordering {
        var i = 0usize
        while i < self.len() && i < other.len() {
            let order = self[i].cmp(read other[i])
            if !order.is_eq() { return order }
            i += 1usize
        }
        self.len().cmp(other.len())
    }
}
// Arrays compare element-wise in index order, like their slices.
extend<T: PartialEq<U>, U, const N: usize> [T; N] implements PartialEq<[U; N]> {
    fn eq(read other: [U; N]): bool {
        var i = 0usize
        while i < N {
            if self[i] != other[i] { return false }
            i += 1usize
        }
        true
    }
}
extend<T: PartialEq<U>, U, const N: usize> [T; N]
    implements PartialEq<[U]> {
    fn eq(read other: [U]): bool {
        if N != other.len() { return false }
        var i = 0usize
        while i < N {
            if self[i] != other[i] { return false }
            i += 1usize
        }
        true
    }
}
extend<T: PartialEq<U>, U, const N: usize> [T]
    implements PartialEq<[U; N]> {
    fn eq(read other: [U; N]): bool {
        if self.len() != N { return false }
        var i = 0usize
        while i < N {
            if self[i] != other[i] { return false }
            i += 1usize
        }
        true
    }
}
extend<region r, T: PartialEq<U>, U, const N: usize> [T; N]
    implements PartialEq<read [U] from r> {
    fn eq(read other: read [U] from r): bool {
        [T; N].(PartialEq<[U]>).eq(read self, *other)
    }
}
extend<region r, T: PartialEq<U>, U, const N: usize> [T; N]
    implements PartialEq<mut [U] from r> {
    fn eq(read other: mut [U] from r): bool {
        [T; N].(PartialEq<[U]>).eq(read self, *other)
    }
}
extend<T: Eq, const N: usize> [T; N] implements Eq {}
extend<T: PartialOrd, const N: usize> [T; N] implements PartialOrd {
    fn partial_cmp(read other: [T; N]): Ordering? {
        var i = 0usize
        while i < N {
            match self[i].partial_cmp(read other[i]) {
                present(order) => if !order.is_eq() { return present(order) },
                none => { return none }
            }
            i += 1usize
        }
        present(Ordering.Equal)
    }
}
extend<T: Ord, const N: usize> [T; N] implements Ord {
    fn cmp(read other: [T; N]): Ordering {
        var i = 0usize
        while i < N {
            let order = self[i].cmp(read other[i])
            if !order.is_eq() { return order }
            i += 1usize
        }
        Ordering.Equal
    }
}

extend<T: PartialEq<U>, U> T? implements PartialEq<U?> {
    fn eq(read other: U?): bool {
        match self {
            present(left) => match other { present(right) => left == right, none => false },
            none => match other { present(right) => false, none => true }
        }
    }
}
extend<T: Eq> T? implements Eq {}
// `none` orders before any present value.
extend<T: PartialOrd<U>, U> T? implements PartialOrd<U?> {
    fn partial_cmp(read other: U?): Ordering? {
        match self {
            present(left) => match other {
                present(right) => left.partial_cmp(right),
                none => present(Ordering.Greater)
            },
            none => match other {
                present(right) => present(Ordering.Less),
                none => present(Ordering.Equal)
            }
        }
    }
}
extend<T: Ord> T? implements Ord {
    fn cmp(read other: T?): Ordering {
        match self {
            present(left) => match other { present(right) => left.cmp(right), none => Ordering.Greater },
            none => match other { present(right) => Ordering.Less, none => Ordering.Equal }
        }
    }
}

extend Unit implements PartialEq { fn eq(read other: Unit): bool { true } }
extend Unit implements Eq {}
extend Unit implements PartialOrd { fn partial_cmp(read other: Unit): Ordering? { present(Ordering.Equal) } }
extend Unit implements Ord { fn cmp(read other: Unit): Ordering { Ordering.Equal } }

extend<region lhs, region rhs, T: PartialEq<U> + unsized, U: unsized>
    read T from lhs implements PartialEq<read U from rhs> {
    fn eq(read other: read U from rhs): bool {
        T.(PartialEq<U>).eq(read *self, *other)
    }
}
extend<region lhs, region rhs, T: PartialEq<U> + unsized, U: unsized>
    read T from lhs implements PartialEq<mut U from rhs> {
    fn eq(read other: mut U from rhs): bool {
        T.(PartialEq<U>).eq(read *self, *other)
    }
}
extend<region lhs, region rhs, T: PartialEq<U> + unsized, U: unsized>
    mut T from lhs implements PartialEq<read U from rhs> {
    fn eq(read other: read U from rhs): bool {
        T.(PartialEq<U>).eq(read *self, *other)
    }
}
extend<region lhs, region rhs, T: PartialEq<U> + unsized, U: unsized>
    mut T from lhs implements PartialEq<mut U from rhs> {
    fn eq(read other: mut U from rhs): bool {
        T.(PartialEq<U>).eq(read *self, *other)
    }
}
extend<region lhs, T: PartialEq<U>, U, const N: usize>
    read [T] from lhs implements PartialEq<[U; N]> {
    fn eq(read other: [U; N]): bool {
        [T].(PartialEq<[U; N]>).eq(read *self, other)
    }
}
extend<region lhs, T: PartialEq<U>, U, const N: usize>
    mut [T] from lhs implements PartialEq<[U; N]> {
    fn eq(read other: [U; N]): bool {
        [T].(PartialEq<[U; N]>).eq(read *self, other)
    }
}
extend<region r, T: Eq + unsized> read T from r implements Eq {}
extend<region r, T: Eq + unsized> mut T from r implements Eq {}
extend<region lhs, region rhs, T: PartialOrd<U> + unsized, U: unsized>
    read T from lhs implements PartialOrd<read U from rhs> {
    fn partial_cmp(read other: read U from rhs): Ordering? {
        T.(PartialOrd<U>).partial_cmp(read *self, *other)
    }
}
extend<region lhs, region rhs, T: PartialOrd<U> + unsized, U: unsized>
    read T from lhs implements PartialOrd<mut U from rhs> {
    fn partial_cmp(read other: mut U from rhs): Ordering? {
        T.(PartialOrd<U>).partial_cmp(read *self, *other)
    }
}
extend<region lhs, region rhs, T: PartialOrd<U> + unsized, U: unsized>
    mut T from lhs implements PartialOrd<read U from rhs> {
    fn partial_cmp(read other: read U from rhs): Ordering? {
        T.(PartialOrd<U>).partial_cmp(read *self, *other)
    }
}
extend<region lhs, region rhs, T: PartialOrd<U> + unsized, U: unsized>
    mut T from lhs implements PartialOrd<mut U from rhs> {
    fn partial_cmp(read other: mut U from rhs): Ordering? {
        T.(PartialOrd<U>).partial_cmp(read *self, *other)
    }
}
extend<region r, T: Ord + unsized> read T from r implements Ord {
    fn cmp(read other: Self): Ordering {
        T.(Ord).cmp(read *self, *other)
    }
}
extend<region r, T: Ord + unsized> mut T from r implements Ord {
    fn cmp(read other: Self): Ordering {
        T.(Ord).cmp(read *self, *other)
    }
}
