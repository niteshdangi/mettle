// Comparison capabilities. Operators dispatch to `PartialEq`/`PartialOrd` by
// these canonical paths; the primitive implementations below delegate to the
// compiler's built-in scalar comparisons.
import super.text.Text
import super.default.Default
import super.fmt.{ Debug, Formatter, Error }

pub copy enum Ordering { Less, Equal, Greater }

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
// Requires low <= high.
pub fn clamp<T: Ord>(take value: T, take low: T, take high: T): T {
    if low.cmp(read high).is_gt() { super.panic.panic("clamp requires low <= high") }
    if value.cmp(read low).is_lt() { low } else if high.cmp(read value).is_lt() { high } else { value }
}

// Inverts the order of the wrapped value.
pub type Reverse<T> { pub value: T }
extend<T: PartialEq> Reverse<T> implements PartialEq { fn eq(read other: Reverse<T>): bool { other.value == self.value } }
extend<T: Eq> Reverse<T> implements Eq {}
extend<T: super.clone.Clone> Reverse<T> implements super.clone.Clone {
    fn clone(): Reverse<T> { Reverse(self.value.clone()) }
}
extend<T: PartialOrd> Reverse<T> implements PartialOrd {
    fn partial_cmp(read other: Reverse<T>): Ordering? { other.value.partial_cmp(read self.value) }
}
extend<T: Ord> Reverse<T> implements Ord { fn cmp(read other: Reverse<T>): Ordering { other.value.cmp(read self.value) } }
extend<T: Default> Reverse<T> implements Default {
    static fn default(): Reverse<T> { Reverse(T.(Default).default()) }
}
extend<T: Debug> Reverse<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var debug = try f.debug_tuple("Reverse")
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
    ($($prefix:ident => $prefix_field:literal,)* ; $last:ident => $last_field:literal) => {
        extend<$($prefix: PartialEq,)* $last: PartialEq + unsized> ($($prefix,)* $last,) implements PartialEq {
            fn eq(read other: ($($prefix,)* $last,)): bool {
        $(self.$prefix_field == other.$prefix_field &&)*
                self.$last_field == other.$last_field
            }
        }

        extend<$($prefix: Eq,)* $last: Eq + unsized> ($($prefix,)* $last,) implements Eq {}

        extend<$($prefix: PartialOrd,)* $last: PartialOrd + unsized> ($($prefix,)* $last,) implements PartialOrd {
            fn partial_cmp(read other: ($($prefix,)* $last,)): Ordering? {
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

tuple_comparison!(; A => 0)
tuple_comparison!(A => 0, ; B => 1)
tuple_comparison!(A => 0, B => 1, ; C => 2)
tuple_comparison!(A => 0, B => 1, C => 2, ; D => 3)
tuple_comparison!(A => 0, B => 1, C => 2, D => 3, ; E => 4)
tuple_comparison!(A => 0, B => 1, C => 2, D => 3, E => 4, ; F => 5)
tuple_comparison!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, ; G => 6)
tuple_comparison!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, G => 6, ; H => 7)
tuple_comparison!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, G => 6, H => 7, ; I => 8)
tuple_comparison!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, G => 6, H => 7, I => 8, ; J => 9)
tuple_comparison!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, G => 6, H => 7, I => 8, J => 9, ; K => 10)
tuple_comparison!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, G => 6, H => 7, I => 8, J => 9, K => 10, ; L => 11)
extend<T: PartialEq> [T] implements PartialEq {
    fn eq(read other: [T]): bool {
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
extend<T: PartialEq, const N: usize> [T; N] implements PartialEq {
    fn eq(read other: [T; N]): bool {
        var i = 0usize
        while i < N {
            if self[i] != other[i] { return false }
            i += 1usize
        }
        true
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

extend<T: PartialEq> T? implements PartialEq {
    fn eq(read other: T?): bool {
        match self {
            present(left) => match other { present(right) => left == right, none => false },
            none => match other { present(right) => false, none => true }
        }
    }
}
extend<T: Eq> T? implements Eq {}
// `none` orders before any present value.
extend<T: PartialOrd> T? implements PartialOrd {
    fn partial_cmp(read other: T?): Ordering? {
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
