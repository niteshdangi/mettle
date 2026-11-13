import super.default.Default
import super.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import super.clone.Clone
import super.fmt.{Debug, Error, Formatter}
import super.hash.{Hash, Hasher}
import super.ops.{Deref, DerefMut}

extend<T: unsized> core.mem.ManuallyDrop<T> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get_ref() }
}

extend<T: unsized> core.mem.ManuallyDrop<T> implements DerefMut {
    mut fn deref_mut(): mut T from self { self.get_mut() }
}

extend<T: unsized> core.mem.ManuallyDrop<T> {
    // The payload must be initialized and neither reused nor dropped again.
    pub unsafe mut fn `drop`(): Unit {
        unsafe { core.ptr.drop_in_place(core.ptr.from_mut(self.get_mut())) }
    }
}

extend<T: Clone> core.mem.ManuallyDrop<T> implements Clone {
    fn clone(): core.mem.ManuallyDrop<T> {
        core.mem.ManuallyDrop.new(self.deref().clone())
    }
}

extend<T: PartialEq + unsized> core.mem.ManuallyDrop<T> implements PartialEq {
    fn eq(read other: core.mem.ManuallyDrop<T>): bool {
        self.deref() == other.deref()
    }
}

extend<T: Eq + unsized> core.mem.ManuallyDrop<T> implements Eq {}

extend<T: PartialOrd + unsized> core.mem.ManuallyDrop<T> implements PartialOrd {
    fn partial_cmp(read other: core.mem.ManuallyDrop<T>): Ordering? {
        self.deref().partial_cmp(other.deref())
    }
}

extend<T: Ord + unsized> core.mem.ManuallyDrop<T> implements Ord {
    fn cmp(read other: core.mem.ManuallyDrop<T>): Ordering {
        self.deref().cmp(other.deref())
    }
}

extend<T: Default> core.mem.ManuallyDrop<T> implements Default {
    static fn default(): core.mem.ManuallyDrop<T> {
        core.mem.ManuallyDrop.new(T.(Default).default())
    }
}

extend<T: Debug + unsized> core.mem.ManuallyDrop<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try self.deref().fmt(mut f)
    }
}

extend<T: Hash + unsized> core.mem.ManuallyDrop<T> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        self.deref().hash(mut state)
    }
}

pub fn `drop`<T>(take value: T): Unit {}

pub fn `take`<T: Default>(mut value: T): T {
    core.mem.replace(mut value, T.(Default).default())
}

extend<T> [core.mem.MaybeUninit<T>] {
    // Every element must hold a valid T with the same lifetime and access permissions.
    pub unsafe const fn assume_init_ref(): read [T] from self {
        let pointer = unsafe {
            core.mem.transmute<ptr<read [T]>>(core.ptr.from_ref(self))
        }
        unsafe { read *pointer }
    }

    // Every element must hold a valid T and remain exclusively borrowed.
    pub mut unsafe const fn assume_init_mut(): mut [T] from self {
        let pointer = unsafe {
            core.mem.transmute<ptr<mut [T]>>(core.ptr.from_mut(self))
        }
        unsafe { mut *pointer }
    }

    // Every element is initialized and may be destroyed exactly once.
    pub mut unsafe fn assume_init_drop(): Unit {
        let count = self.len()
        let data = core.ptr.from_mut(self).cast<T>()
        unsafe { super.slice.drop_values(data, count) }
    }

    pub mut const fn write_copy_of_slice(read source: [T]): mut [T] from self where T: Copy {
        if source.len() > self.len() { super.panic.panic("destination slice is too short") }
        var index = 0usize
        while index < source.len() {
            let value = source[index]
            self[index].write(value)
            index += 1usize
        }
        // Safety: the length check above bounds the prefix by the destination.
        let prefix = unsafe { super.slice.sub_mut<core.mem.MaybeUninit<T>>(mut self, 0usize, source.len()) }
        unsafe { prefix.assume_init_mut() }
    }

    pub mut fn write_clone_of_slice(read source: [T]): mut [T] from self where T: Clone {
        if source.len() > self.len() { super.panic.panic("destination slice is too short") }
        let data = core.ptr.from_mut(self).cast<T>()
        var guard = SliceCloneGuard(data, 0usize)
        while guard.initialized < source.len() {
            self[guard.initialized].write(source[guard.initialized].clone())
            guard.initialized += 1usize
        }
        guard.initialized = 0usize
        let prefix = mut self[..source.len()]
        unsafe { prefix.assume_init_mut() }
    }
}

type SliceCloneGuard<T> {
    data: ptr<mut T>
    initialized: usize
    drop {
        let count = self.initialized
        self.initialized = 0usize
        // Only clones committed before a panic are initialized and owned by this guard.
        unsafe { super.slice.drop_values(self.data, count) }
    }
}
