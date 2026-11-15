import super.cmp.{Eq, PartialEq}
import super.clone.Clone
import super.hash.{Hash, Hasher}

pub copy type Range<T> { pub start: T; pub end: T }
extend<T: Clone> Range<T> implements Clone {
    fn clone(): Range<T> { Range(self.start.clone(), self.end.clone()) }
}
extend<T: PartialEq> Range<T> implements PartialEq {
    fn eq(read other: Range<T>): bool { self.start == other.start && self.end == other.end }
}
extend<T: Eq> Range<T> implements Eq {}
extend<T: Hash> Range<T> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        self.start.hash(mut state)
        self.end.hash(mut state)
    }
}

pub copy type RangeFrom<T> { pub start: T }
extend<T: Clone> RangeFrom<T> implements Clone {
    fn clone(): RangeFrom<T> { RangeFrom(self.start.clone()) }
}
extend<T: PartialEq> RangeFrom<T> implements PartialEq {
    fn eq(read other: RangeFrom<T>): bool { self.start == other.start }
}
extend<T: Eq> RangeFrom<T> implements Eq {}
extend<T: Hash> RangeFrom<T> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.start.hash(mut state) }
}

pub copy type RangeInclusive<T> { pub start: T; pub last: T }
extend<T: Clone> RangeInclusive<T> implements Clone {
    fn clone(): RangeInclusive<T> { RangeInclusive(self.start.clone(), self.last.clone()) }
}
extend<T: PartialEq> RangeInclusive<T> implements PartialEq {
    fn eq(read other: RangeInclusive<T>): bool {
        self.start == other.start && self.last == other.last
    }
}
extend<T: Eq> RangeInclusive<T> implements Eq {}
extend<T: Hash> RangeInclusive<T> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        self.start.hash(mut state)
        self.last.hash(mut state)
    }
}

pub copy type RangeTo<T> { pub end: T }
extend<T: Clone> RangeTo<T> implements Clone {
    fn clone(): RangeTo<T> { RangeTo(self.end.clone()) }
}
extend<T: PartialEq> RangeTo<T> implements PartialEq {
    fn eq(read other: RangeTo<T>): bool { self.end == other.end }
}
extend<T: Eq> RangeTo<T> implements Eq {}
extend<T: Hash> RangeTo<T> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.end.hash(mut state) }
}

pub copy type RangeToInclusive<T> { pub last: T }
extend<T: Clone> RangeToInclusive<T> implements Clone {
    fn clone(): RangeToInclusive<T> { RangeToInclusive(self.last.clone()) }
}
extend<T: PartialEq> RangeToInclusive<T> implements PartialEq {
    fn eq(read other: RangeToInclusive<T>): bool { self.last == other.last }
}
extend<T: Eq> RangeToInclusive<T> implements Eq {}
extend<T: Hash> RangeToInclusive<T> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.last.hash(mut state) }
}

pub copy type RangeFull {}
extend RangeFull implements Clone { fn clone(): RangeFull { self } }
extend RangeFull implements PartialEq { fn eq(read other: RangeFull): bool { true } }
extend RangeFull implements Eq {}
extend RangeFull implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {}
}
