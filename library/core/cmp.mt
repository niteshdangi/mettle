// Comparison capabilities. Operators dispatch to `PartialEq`/`PartialOrd` by
// these canonical paths; the primitive implementations below delegate to the
// compiler's built-in scalar comparisons.
import super::text::Text;

pub copy enum Ordering { Less, Equal, Greater }

impl Ordering {
    pub fn is_lt(): bool { match self { Ordering::Less => true, Ordering::Equal => false, Ordering::Greater => false } }
    pub fn is_le(): bool { match self { Ordering::Greater => false, Ordering::Less => true, Ordering::Equal => true } }
    pub fn is_gt(): bool { match self { Ordering::Greater => true, Ordering::Equal => false, Ordering::Less => false } }
    pub fn is_ge(): bool { match self { Ordering::Less => false, Ordering::Equal => true, Ordering::Greater => true } }
    pub fn is_eq(): bool { match self { Ordering::Equal => true, Ordering::Less => false, Ordering::Greater => false } }
    pub fn is_ne(): bool { !self.is_eq() }
    pub fn reverse(): Ordering {
        match self { Ordering::Less => Ordering::Greater, Ordering::Equal => Ordering::Equal, Ordering::Greater => Ordering::Less }
    }
    // Lexicographic combination: `other` only decides when `self` is Equal.
    pub fn then(other: Ordering): Ordering {
        match self { Ordering::Equal => other, Ordering::Less => Ordering::Less, Ordering::Greater => Ordering::Greater }
    }
    pub fn then_with(other: fn(): Ordering): Ordering {
        match self { Ordering::Equal => other(), Ordering::Less => Ordering::Less, Ordering::Greater => Ordering::Greater }
    }
}

pub interface PartialEq<Rhs: unsized = Self> {
    fn eq(other: read Rhs): bool;
    fn ne(other: read Rhs): bool { !self.eq(other) }
}

// Marker: `eq` is reflexive, symmetric and transitive.
pub interface Eq: PartialEq {}

pub interface PartialOrd<Rhs: unsized = Self>: PartialEq<Rhs> {
    fn partial_cmp(other: read Rhs): Ordering?;
    fn lt(other: read Rhs): bool {
        match self.partial_cmp(other) { present(o) => o.is_lt(), none => false }
    }
    fn le(other: read Rhs): bool {
        match self.partial_cmp(other) { present(o) => o.is_le(), none => false }
    }
    fn gt(other: read Rhs): bool {
        match self.partial_cmp(other) { present(o) => o.is_gt(), none => false }
    }
    fn ge(other: read Rhs): bool {
        match self.partial_cmp(other) { present(o) => o.is_ge(), none => false }
    }
}

// Total order consistent with `PartialOrd` and `Eq`.
pub interface Ord: Eq + PartialOrd {
    fn cmp(other: read Self): Ordering;
}

pub fn min<T: Ord>(a: take T, b: take T): T { if b.cmp(read a).is_lt() { b } else { a } }
pub fn max<T: Ord>(a: take T, b: take T): T { if b.cmp(read a).is_lt() { a } else { b } }
// Requires low <= high.
pub fn clamp<T: Ord>(value: take T, low: take T, high: take T): T {
    if value.cmp(read low).is_lt() { low } else if high.cmp(read value).is_lt() { high } else { value }
}

// Inverts the order of the wrapped value.
pub type Reverse<T> { pub value: T }
impl<T: PartialEq> Reverse<T> implements PartialEq { fn eq(other: read Reverse<T>): bool { other.value == self.value } }
impl<T: Eq> Reverse<T> implements Eq {}
impl<T: PartialOrd> Reverse<T> implements PartialOrd {
    fn partial_cmp(other: read Reverse<T>): Ordering? { other.value.partial_cmp(read self.value) }
}
impl<T: Ord> Reverse<T> implements Ord { fn cmp(other: read Reverse<T>): Ordering { other.value.cmp(read self.value) } }

impl Ordering implements PartialEq {
    fn eq(other: read Ordering): bool {
        match self {
            Ordering::Less => other.is_lt(),
            Ordering::Equal => other.is_eq(),
            Ordering::Greater => other.is_gt()
        }
    }
}
impl Ordering implements Eq {}

impl i8 implements PartialEq { fn eq(other: read i8): bool { self == other } }
impl i8 implements Eq {}
impl i8 implements PartialOrd {
    fn partial_cmp(other: read i8): Ordering? { present(self.cmp(other)) }
}
impl i8 implements Ord {
    fn cmp(other: read i8): Ordering {
        if self < other { Ordering::Less } else if self == other { Ordering::Equal } else { Ordering::Greater }
    }
}

impl i16 implements PartialEq { fn eq(other: read i16): bool { self == other } }
impl i16 implements Eq {}
impl i16 implements PartialOrd {
    fn partial_cmp(other: read i16): Ordering? { present(self.cmp(other)) }
}
impl i16 implements Ord {
    fn cmp(other: read i16): Ordering {
        if self < other { Ordering::Less } else if self == other { Ordering::Equal } else { Ordering::Greater }
    }
}

impl i32 implements PartialEq { fn eq(other: read i32): bool { self == other } }
impl i32 implements Eq {}
impl i32 implements PartialOrd {
    fn partial_cmp(other: read i32): Ordering? { present(self.cmp(other)) }
}
impl i32 implements Ord {
    fn cmp(other: read i32): Ordering {
        if self < other { Ordering::Less } else if self == other { Ordering::Equal } else { Ordering::Greater }
    }
}

impl i64 implements PartialEq { fn eq(other: read i64): bool { self == other } }
impl i64 implements Eq {}
impl i64 implements PartialOrd {
    fn partial_cmp(other: read i64): Ordering? { present(self.cmp(other)) }
}
impl i64 implements Ord {
    fn cmp(other: read i64): Ordering {
        if self < other { Ordering::Less } else if self == other { Ordering::Equal } else { Ordering::Greater }
    }
}

impl isize implements PartialEq { fn eq(other: read isize): bool { self == other } }
impl isize implements Eq {}
impl isize implements PartialOrd {
    fn partial_cmp(other: read isize): Ordering? { present(self.cmp(other)) }
}
impl isize implements Ord {
    fn cmp(other: read isize): Ordering {
        if self < other { Ordering::Less } else if self == other { Ordering::Equal } else { Ordering::Greater }
    }
}

impl u8 implements PartialEq { fn eq(other: read u8): bool { self == other } }
impl u8 implements Eq {}
impl u8 implements PartialOrd {
    fn partial_cmp(other: read u8): Ordering? { present(self.cmp(other)) }
}
impl u8 implements Ord {
    fn cmp(other: read u8): Ordering {
        if self < other { Ordering::Less } else if self == other { Ordering::Equal } else { Ordering::Greater }
    }
}

impl u16 implements PartialEq { fn eq(other: read u16): bool { self == other } }
impl u16 implements Eq {}
impl u16 implements PartialOrd {
    fn partial_cmp(other: read u16): Ordering? { present(self.cmp(other)) }
}
impl u16 implements Ord {
    fn cmp(other: read u16): Ordering {
        if self < other { Ordering::Less } else if self == other { Ordering::Equal } else { Ordering::Greater }
    }
}

impl u32 implements PartialEq { fn eq(other: read u32): bool { self == other } }
impl u32 implements Eq {}
impl u32 implements PartialOrd {
    fn partial_cmp(other: read u32): Ordering? { present(self.cmp(other)) }
}
impl u32 implements Ord {
    fn cmp(other: read u32): Ordering {
        if self < other { Ordering::Less } else if self == other { Ordering::Equal } else { Ordering::Greater }
    }
}

impl u64 implements PartialEq { fn eq(other: read u64): bool { self == other } }
impl u64 implements Eq {}
impl u64 implements PartialOrd {
    fn partial_cmp(other: read u64): Ordering? { present(self.cmp(other)) }
}
impl u64 implements Ord {
    fn cmp(other: read u64): Ordering {
        if self < other { Ordering::Less } else if self == other { Ordering::Equal } else { Ordering::Greater }
    }
}

impl usize implements PartialEq { fn eq(other: read usize): bool { self == other } }
impl usize implements Eq {}
impl usize implements PartialOrd {
    fn partial_cmp(other: read usize): Ordering? { present(self.cmp(other)) }
}
impl usize implements Ord {
    fn cmp(other: read usize): Ordering {
        if self < other { Ordering::Less } else if self == other { Ordering::Equal } else { Ordering::Greater }
    }
}

impl char implements PartialEq { fn eq(other: read char): bool { self == other } }
impl char implements Eq {}
impl char implements PartialOrd {
    fn partial_cmp(other: read char): Ordering? { present(self.cmp(other)) }
}
impl char implements Ord {
    fn cmp(other: read char): Ordering {
        if self < other { Ordering::Less } else if self == other { Ordering::Equal } else { Ordering::Greater }
    }
}

impl bool implements PartialEq { fn eq(other: read bool): bool { (self as u8) == (other as u8) } }
impl bool implements Eq {}
impl bool implements PartialOrd {
    fn partial_cmp(other: read bool): Ordering? { present(self.cmp(other)) }
}
impl bool implements Ord {
    fn cmp(other: read bool): Ordering {
        if (self as u8) < (other as u8) { Ordering::Less } else if (self as u8) == (other as u8) { Ordering::Equal } else { Ordering::Greater }
    }
}

impl<A: PartialEq, B: PartialEq> (A, B) implements PartialEq {
    fn eq(other: read (A, B)): bool { self.0 == other.0 && self.1 == other.1 }
}
impl<A: Eq, B: Eq> (A, B) implements Eq {}
impl<A: PartialOrd, B: PartialOrd> (A, B) implements PartialOrd {
    fn partial_cmp(other: read (A, B)): Ordering? {
        match self.0.partial_cmp(read other.0) {
            present(first) => if first.is_eq() { self.1.partial_cmp(read other.1) } else { present(first) },
            none => none
        }
    }
}
impl<A: Ord, B: Ord> (A, B) implements Ord {
    fn cmp(other: read (A, B)): Ordering {
        let first = self.0.cmp(read other.0)
        if first.is_eq() { self.1.cmp(read other.1) } else { first }
    }
}

impl<T: PartialEq> [T] implements PartialEq {
    fn eq(other: read [T]): bool {
        if self.len() != other.len() { return false }
        var i = 0usize
        while i < self.len() {
            if self[i] != other[i] { return false }
            i += 1usize
        }
        true
    }
}
impl<T: Eq> [T] implements Eq {}
impl<T: PartialOrd> [T] implements PartialOrd {
    fn partial_cmp(other: read [T]): Ordering? {
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
impl<T: Ord> [T] implements Ord {
    fn cmp(other: read [T]): Ordering {
        var i = 0usize
        while i < self.len() && i < other.len() {
            let order = self[i].cmp(read other[i])
            if !order.is_eq() { return order }
            i += 1usize
        }
        self.len().cmp(other.len())
    }
}

impl<T: PartialEq> T? implements PartialEq {
    fn eq(other: read T?): bool {
        match self {
            present(left) => match other { present(right) => left == right, none => false },
            none => match other { present(right) => false, none => true }
        }
    }
}
impl<T: Eq> T? implements Eq {}
// `none` orders before any present value.
impl<T: PartialOrd> T? implements PartialOrd {
    fn partial_cmp(other: read T?): Ordering? {
        match self {
            present(left) => match other {
                present(right) => left.partial_cmp(right),
                none => present(Ordering::Greater)
            },
            none => match other {
                present(right) => present(Ordering::Less),
                none => present(Ordering::Equal)
            }
        }
    }
}
impl<T: Ord> T? implements Ord {
    fn cmp(other: read T?): Ordering {
        match self {
            present(left) => match other { present(right) => left.cmp(right), none => Ordering::Greater },
            none => match other { present(right) => Ordering::Less, none => Ordering::Equal }
        }
    }
}

impl Unit implements PartialEq { fn eq(other: read Unit): bool { true } }
impl Unit implements Eq {}
impl Unit implements PartialOrd { fn partial_cmp(other: read Unit): Ordering? { present(Ordering::Equal) } }
impl Unit implements Ord { fn cmp(other: read Unit): Ordering { Ordering::Equal } }
