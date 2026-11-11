import super.default.Default
import super.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import super.clone.Clone
import super.fmt.{Debug, Error, Formatter}
import super.hash.{Hash, Hasher}
import super.ops.{Deref, DerefMut}

// Projections rely on ManuallyDrop's T layout and an initialized payload.
extend<T> core.mem.ManuallyDrop<T> implements Deref {
    type Target = T
    fn deref(): read T from self {
        unsafe { read *core.ptr.from_ref(self).cast<T>() }
    }
}

extend<T> core.mem.ManuallyDrop<T> implements DerefMut {
    mut fn deref_mut(): mut T from self {
        unsafe { mut *core.ptr.from_mut(mut self).cast<T>() }
    }
}

extend<T> core.mem.ManuallyDrop<T> {
    // The payload must be initialized and neither reused nor dropped again.
    pub unsafe mut fn `drop`(): Unit {
        unsafe { core.ptr.drop_in_place(core.ptr.from_mut(mut self).cast<T>()) }
    }
}

extend<T: Clone> core.mem.ManuallyDrop<T> implements Clone {
    fn clone(): core.mem.ManuallyDrop<T> {
        core.mem.ManuallyDrop.new(self.deref().clone())
    }
}

extend<T: PartialEq> core.mem.ManuallyDrop<T> implements PartialEq {
    fn eq(read other: core.mem.ManuallyDrop<T>): bool {
        self.deref() == other.deref()
    }
}

extend<T: Eq> core.mem.ManuallyDrop<T> implements Eq {}

extend<T: PartialOrd> core.mem.ManuallyDrop<T> implements PartialOrd {
    fn partial_cmp(read other: core.mem.ManuallyDrop<T>): Ordering? {
        self.deref().partial_cmp(other.deref())
    }
}

extend<T: Ord> core.mem.ManuallyDrop<T> implements Ord {
    fn cmp(read other: core.mem.ManuallyDrop<T>): Ordering {
        self.deref().cmp(other.deref())
    }
}

extend<T: Default> core.mem.ManuallyDrop<T> implements Default {
    static fn default(): core.mem.ManuallyDrop<T> {
        core.mem.ManuallyDrop.new(T.(Default).default())
    }
}

extend<T: Debug> core.mem.ManuallyDrop<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try self.deref().fmt(mut f)
    }
}

extend<T: Hash> core.mem.ManuallyDrop<T> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        self.deref().hash(mut state)
    }
}

pub fn `drop`<T>(take value: T): Unit {}

pub fn `take`<T: Default>(mut value: T): T {
    core.mem.replace(mut value, T.(Default).default())
}
