import super.clone.Clone
import super.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import super.fmt.{Debug, Display, Error, Formatter}
import super.future.{Context, Future, Poll}
import super.hash.{Hash, Hasher}
import super.ops.{Deref, DerefMut}

pub module Pin {
    pub const fn static_ref<T: unsized>(
        value: read T from static
    ): pinned read T from static {
        unsafe { core.pin.Pin.new_unchecked(value) }
    }

    pub const fn static_mut<T: unsized>(
        take value: mut T from static
    ): pinned mut T from static {
        unsafe { core.pin.Pin.new_unchecked(take value) }
    }
}

extend<region r, T> pinned mut T from r {
    pub mut fn set(take value: T): Unit {
        unsafe { *self.get_unchecked_mut() = value }
    }
}

extend<region r, T: unsized> pinned mut T from r {
    pub take fn into_ref(): pinned read T from self {
        // The source pin already guarantees the pointee's address is stable.
        let value = unsafe { take self.into_inner_unchecked() }
        unsafe { core.pin.Pin.new_unchecked(read *value) }
    }

    // The caller must ensure the returned view remains pinned for region r.
    pub take unsafe fn map_unchecked<U: unsized, F: for<region s> take fn(
        read T from s
    ): read U from s>(take f: F): pinned read U from self {
        let value = unsafe { take self.into_inner_unchecked() }
        unsafe { core.pin.Pin.new_unchecked(f(read *value)) }
    }

    // The caller must ensure the returned view remains pinned for region r.
    pub mut unsafe fn map_unchecked_mut<U: unsized, F: for<region s> take fn(
        mut T from s
    ): mut U from s>(take f: F): pinned mut U from self {
        let target = f(unsafe { self.get_unchecked_mut() })
        unsafe { core.pin.Pin.new_unchecked(target) }
    }
}

extend<region r, region s, T: PartialEq<U> + unsized, U: unsized> pinned read T from r implements PartialEq<pinned read U from s> {
    fn eq(read other: pinned read U from s): bool { self.get_ref().eq(other.get_ref()) }
}

extend<region r, T: Eq + unsized> pinned read T from r implements Eq {}

extend<region r, region s, T: PartialOrd<U> + unsized, U: unsized> pinned read T from r implements PartialOrd<pinned read U from s> {
    fn partial_cmp(read other: pinned read U from s): Ordering? {
        self.get_ref().partial_cmp(other.get_ref())
    }
}

extend<region r, T: Ord + unsized> pinned read T from r implements Ord {
    fn cmp(read other: Self): Ordering { self.get_ref().cmp(other.get_ref()) }
}

extend<region r, T: unsized> pinned read T from r implements Clone {
    fn clone(): Self { self }
}

extend<region r, T: Hash + unsized> pinned read T from r implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.get_ref().hash(mut state) }
}

extend<region r, T: Debug + unsized> pinned read T from r implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try T.(Debug).fmt(self.get_ref(), mut f) }
}

extend<region r, T: Display + unsized> pinned read T from r implements Display {
    fn fmt(mut f: Formatter): Unit throws Error { try T.(Display).fmt(self.get_ref(), mut f) }
}

extend<region r, region s, T: PartialEq<U> + unsized, U: unsized> pinned mut T from r implements PartialEq<pinned mut U from s> {
    fn eq(read other: pinned mut U from s): bool { self.get_ref().eq(other.get_ref()) }
}

extend<region r, region s, T: PartialEq<U> + unsized, U: unsized> pinned mut T from r implements PartialEq<pinned read U from s> {
    fn eq(read other: pinned read U from s): bool { self.get_ref().eq(other.get_ref()) }
}

extend<region r, region s, T: PartialEq<U> + unsized, U: unsized> pinned read T from r implements PartialEq<pinned mut U from s> {
    fn eq(read other: pinned mut U from s): bool { self.get_ref().eq(other.get_ref()) }
}

extend<region r, T: Eq + unsized> pinned mut T from r implements Eq {}

extend<region r, region s, T: PartialOrd<U> + unsized, U: unsized> pinned mut T from r implements PartialOrd<pinned mut U from s> {
    fn partial_cmp(read other: pinned mut U from s): Ordering? {
        self.get_ref().partial_cmp(other.get_ref())
    }
}

extend<region r, region s, T: PartialOrd<U> + unsized, U: unsized> pinned mut T from r implements PartialOrd<pinned read U from s> {
    fn partial_cmp(read other: pinned read U from s): Ordering? {
        self.get_ref().partial_cmp(other.get_ref())
    }
}

extend<region r, region s, T: PartialOrd<U> + unsized, U: unsized> pinned read T from r implements PartialOrd<pinned mut U from s> {
    fn partial_cmp(read other: pinned mut U from s): Ordering? {
        self.get_ref().partial_cmp(other.get_ref())
    }
}

extend<region r, T: Ord + unsized> pinned mut T from r implements Ord {
    fn cmp(read other: Self): Ordering { self.get_ref().cmp(other.get_ref()) }
}

extend<region r, T: Hash + unsized> pinned mut T from r implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.get_ref().hash(mut state) }
}

extend<region r, T: Debug + unsized> pinned mut T from r implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try T.(Debug).fmt(self.get_ref(), mut f) }
}

extend<region r, T: Display + unsized> pinned mut T from r implements Display {
    fn fmt(mut f: Formatter): Unit throws Error { try T.(Display).fmt(self.get_ref(), mut f) }
}

extend<region r, T: unsized> pinned read T from r implements Deref {
    type Target = T
    fn deref(): read T from self { self.get_ref() }
}

extend<region r, T: unsized> pinned mut T from r implements Deref {
    type Target = T
    fn deref(): read T from self { self.get_ref() }
}

extend<region r, T: Unpin + unsized> pinned mut T from r implements DerefMut {
    mut fn deref_mut(): mut T from self { self.get_mut() }
}

extend<region r, T: Future + unsized> pinned mut T from r implements Future {
    type Output = T.(Future).Output
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<T.(Future).Output> {
        T.(Future).poll(self.get_mut().as_mut(), mut cx)
    }
}
