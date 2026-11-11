import super.clone.Clone
import super.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import super.fmt.{Debug, Display, Error, Formatter}
import super.hash.{Hash, Hasher}

extend<region r, T> pinned mut T from r {
    pub mut fn set(take value: T): Unit {
        unsafe { *self.get_unchecked_mut() = value }
    }

    pub take fn into_ref(): pinned read T from self {
        // The source pin already guarantees the pointee's address is stable.
        let value = unsafe { take self.into_inner_unchecked() }
        unsafe { core.pin.Pin.new_unchecked(read *value) }
    }

    // The caller must ensure the returned view remains pinned for region r.
    pub take unsafe fn map_unchecked<U, F: for<region s> take fn(
        read T from s
    ): read U from s>(take f: F): pinned read U from self {
        let value = unsafe { take self.into_inner_unchecked() }
        unsafe { core.pin.Pin.new_unchecked(f(read *value)) }
    }

    // The caller must ensure the returned view remains pinned for region r.
    pub mut unsafe fn map_unchecked_mut<U, F: for<region s> take fn(
        mut T from s
    ): mut U from s>(take f: F): pinned mut U from self {
        let target = f(unsafe { self.get_unchecked_mut() })
        unsafe { core.pin.Pin.new_unchecked(target) }
    }
}

extend<region r, T: PartialEq> pinned read T from r implements PartialEq {
    fn eq(read other: pinned read T from r): bool { self.get_ref().eq(other.get_ref()) }
}

extend<region r, T: Eq> pinned read T from r implements Eq {}

extend<region r, T: PartialOrd> pinned read T from r implements PartialOrd {
    fn partial_cmp(read other: pinned read T from r): Ordering? {
        self.get_ref().partial_cmp(other.get_ref())
    }
}

extend<region r, T: Ord> pinned read T from r implements Ord {
    fn cmp(read other: Self): Ordering { self.get_ref().cmp(other.get_ref()) }
}

extend<region r, T> pinned read T from r implements Clone {
    fn clone(): Self { self }
}

extend<region r, T: Hash> pinned read T from r implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { self.get_ref().hash(mut state) }
}

extend<region r, T: Debug> pinned read T from r implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try T.(Debug).fmt(self.get_ref(), mut f) }
}

extend<region r, T: Display> pinned read T from r implements Display {
    fn fmt(mut f: Formatter): Unit throws Error { try T.(Display).fmt(self.get_ref(), mut f) }
}
