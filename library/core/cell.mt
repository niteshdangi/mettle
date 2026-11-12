import package.core.clone.Clone
import package.core.borrow.AsRef
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.convert.From
import package.core.default.Default
import package.core.fmt
import package.core.ops.{Deref, DerefMut}

extend<T: unsized> core.cell.Ref<T> {
    pub static fn map<region r, U: unsized, F: for<region s> take fn(
        read T from s
    ): read U from s>(
        take original: core.cell.Ref<T> from r, take f: F
    ): core.cell.Ref<U> from r {
        let pointer = core.ptr.from_ref(f(original.get_ref()))
        let projected = unsafe { original.project_unchecked(pointer) }
        core.mem.forget(original)
        projected
    }

    pub static fn filter_map<region r, U: unsized, F: for<region s> take fn(
        read T from s
    ): (read U from s)?>(
        take original: core.cell.Ref<T> from r, take f: F
    ): core.cell.Ref<U> from r throws core.cell.Ref<T> from r {
        let pointer = match f(original.get_ref()) {
            present(value) => core.ptr.from_ref(value),
            none => { throw original }
        }
        let projected = unsafe { original.project_unchecked(pointer) }
        core.mem.forget(original)
        projected
    }

    pub static fn map_split<region r, U: unsized, V: unsized,
        F: for<region s> take fn(read T from s): (
            read U from s, read V from s
        )>(
        take original: core.cell.Ref<T> from r, take f: F
    ): (core.cell.Ref<U> from r, core.cell.Ref<V> from r) {
        let (left, right) = f(original.get_ref())
        let left_pointer = core.ptr.from_ref(left)
        let right_pointer = core.ptr.from_ref(right)
        let second = unsafe { original.split_token_unchecked() }
        let first = unsafe { original.project_unchecked(left_pointer) }
        let last = unsafe { second.project_unchecked(right_pointer) }
        core.mem.forget(original)
        core.mem.forget(second)
        (first, last)
    }
}

extend<T: unsized> core.cell.RefMut<T> {
    pub static fn map<region r, U: unsized, F: for<region s> take fn(
        mut T from s
    ): mut U from s>(
        take original: core.cell.RefMut<T> from r, take f: F
    ): core.cell.RefMut<U> from r {
        var guard = original
        let pointer = core.ptr.from_mut(f(guard.get_mut()))
        let projected = unsafe { guard.project_unchecked(pointer) }
        core.mem.forget(guard)
        projected
    }

    pub static fn filter_map<region r, U: unsized, F: for<region s> take fn(
        mut T from s
    ): (mut U from s)?>(
        take original: core.cell.RefMut<T> from r, take f: F
    ): core.cell.RefMut<U> from r throws core.cell.RefMut<T> from r {
        var guard = original
        let pointer = match take f(guard.get_mut()) {
            present(value) => {
                var projection = value
                core.ptr.from_mut(projection)
            },
            none => { throw guard }
        }
        let projected = unsafe { guard.project_unchecked(pointer) }
        core.mem.forget(guard)
        projected
    }

    pub static fn map_split<region r, U: unsized, V: unsized,
        F: for<region s> take fn(mut T from s): (
            mut U from s, mut V from s
        )>(
        take original: core.cell.RefMut<T> from r, take f: F
    ): (core.cell.RefMut<U> from r, core.cell.RefMut<V> from r) {
        var guard = original
        let (left, right) = f(guard.get_mut())
        let left_pointer = core.ptr.from_mut(left)
        let right_pointer = core.ptr.from_mut(right)
        let second = unsafe { guard.split_token_unchecked() }
        let first = unsafe { guard.project_unchecked(left_pointer) }
        let last = unsafe { second.project_unchecked(right_pointer) }
        core.mem.forget(guard)
        core.mem.forget(second)
        (first, last)
    }
}

extend<T: Copy> core.cell.Cell<T> {
    pub fn update<F: take fn(T): T>(take f: F): Unit {
        self.set(f(self.get()))
    }
}

extend<T: unsized> core.cell.Cell<T> {
    // Cell has one offset-zero payload; preserve the exclusive source loan and metadata.
    pub static const fn from_mut(mut value: T): read core.cell.Cell<T> from value {
        let pointer = unsafe {
            core.ptr.from_mut(value) as ptr<read core.cell.Cell<T>>
        }
        unsafe { read *pointer }
    }
}

extend<T> core.cell.Cell<[T]> {
    // Cell and its payload have identical layout; the fat pointer retains extent and provenance.
    pub const fn as_slice_of_cells(): read [core.cell.Cell<T>] from self {
        let pointer = unsafe {
            self.as_ptr() as ptr<read [core.cell.Cell<T>]>
        }
        unsafe { read *pointer }
    }
}

extend<T, const N: usize> core.cell.Cell<[T; N]> {
    // Each initialized element keeps its original stride, alignment, ownership and source lifetime.
    pub const fn as_array_of_cells(): read [core.cell.Cell<T>; N] from self {
        unsafe { read *self.as_ptr().cast<[core.cell.Cell<T>; N]>() }
    }
}

extend<T> core.cell.Cell<[T]> implements AsRef<[core.cell.Cell<T>]> {
    fn as_ref(): read [core.cell.Cell<T>] from self { self.as_slice_of_cells() }
}

extend<T, const N: usize> core.cell.Cell<[T; N]>
    implements AsRef<[core.cell.Cell<T>; N]> {
    fn as_ref(): read [core.cell.Cell<T>; N] from self { self.as_array_of_cells() }
}

extend<T, const N: usize> core.cell.Cell<[T; N]>
    implements AsRef<[core.cell.Cell<T>]> {
    fn as_ref(): read [core.cell.Cell<T>] from self { self.as_array_of_cells() }
}

extend<T: Default> core.cell.Cell<T> {
    pub fn `take`(): T {
        self.replace(T.(Default).default())
    }
}

extend<T: Default> core.cell.RefCell<T> {
    pub fn `take`(): T {
        self.replace(T.(Default).default())
    }
}

extend<T> core.cell.RefCell<T> {
    pub fn replace_with<F: take fn(mut T): T>(take f: F): T {
        var guard = self.borrow_mut()
        let current = guard.get_mut()
        let replacement = f(current)
        core.mem.replace(current, replacement)
    }
}

extend<T> core.cell.Cell<T> implements From<T> {
    static fn from(take value: T): core.cell.Cell<T> {
        core.cell.Cell.new(value)
    }
}

extend<T: Copy> core.cell.Cell<T> implements Clone {
    fn clone(): core.cell.Cell<T> {
        core.cell.Cell.new(self.get())
    }
}

extend<T: Default> core.cell.Cell<T> implements Default {
    static fn default(): core.cell.Cell<T> {
        core.cell.Cell.new(T.(Default).default())
    }
}

extend<T: Copy + PartialEq> core.cell.Cell<T> implements PartialEq {
    fn eq(read other: core.cell.Cell<T>): bool {
        self.get().eq(other.get())
    }
}

extend<T: Copy + Eq> core.cell.Cell<T> implements Eq {}

extend<T: Copy + PartialOrd> core.cell.Cell<T> implements PartialOrd {
    fn partial_cmp(read other: core.cell.Cell<T>): Ordering? {
        self.get().partial_cmp(other.get())
    }
}

extend<T: Copy + Ord> core.cell.Cell<T> implements Ord {
    fn cmp(read other: core.cell.Cell<T>): Ordering {
        self.get().cmp(other.get())
    }
}

extend<T: Copy + fmt.Debug> core.cell.Cell<T> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var structure = try f.debug_struct("Cell")
        let _ = try structure.field("value", self.get())
        try take structure.finish()
    }
}

extend<T: Clone> core.cell.RefCell<T> implements Clone {
    fn clone(): core.cell.RefCell<T> {
        let value = self.borrow()
        core.cell.RefCell.new(value.get_ref().clone())
    }
}

extend<T> core.cell.RefCell<T> implements From<T> {
    static fn from(take value: T): core.cell.RefCell<T> {
        core.cell.RefCell.new(value)
    }
}

extend<T: Default> core.cell.RefCell<T> implements Default {
    static fn default(): core.cell.RefCell<T> {
        core.cell.RefCell.new(T.(Default).default())
    }
}

extend<T: unsized + PartialEq> core.cell.RefCell<T> implements PartialEq {
    fn eq(read other: core.cell.RefCell<T>): bool {
        let left = self.borrow()
        let right = other.borrow()
        left.get_ref().eq(right.get_ref())
    }
}

extend<T: unsized + Eq> core.cell.RefCell<T> implements Eq {}

extend<T: unsized + PartialOrd> core.cell.RefCell<T> implements PartialOrd {
    fn partial_cmp(read other: core.cell.RefCell<T>): Ordering? {
        let left = self.borrow()
        let right = other.borrow()
        left.get_ref().partial_cmp(right.get_ref())
    }
}

extend<T: unsized + Ord> core.cell.RefCell<T> implements Ord {
    fn cmp(read other: core.cell.RefCell<T>): Ordering {
        let left = self.borrow()
        let right = other.borrow()
        left.get_ref().cmp(right.get_ref())
    }
}

extend<T: unsized + fmt.Debug> core.cell.RefCell<T> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var structure = try f.debug_struct("RefCell")
        match self.try_borrow() {
            success(guard) => {
                let _ = try structure.field("value", guard.get_ref())
            },
            failure(_) => {
                let _ = try structure.field("value", "<borrowed>")
            }
        }
        try take structure.finish()
    }
}

extend<T: unsized + fmt.Debug> core.cell.Ref<T> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.get_ref(), mut f)
    }
}

extend<T: unsized + fmt.Display> core.cell.Ref<T> implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Display).fmt(self.get_ref(), mut f)
    }
}

extend<T: unsized + fmt.Debug> core.cell.RefMut<T> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.get_ref(), mut f)
    }
}

extend<T: unsized + fmt.Display> core.cell.RefMut<T> implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Display).fmt(self.get_ref(), mut f)
    }
}

extend<T: unsized> core.cell.Ref<T> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get_ref() }
}

extend<T: unsized> core.cell.RefMut<T> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get_ref() }
}
extend<T: unsized> core.cell.RefMut<T> implements DerefMut {
    mut fn deref_mut(): mut T from self { self.get_mut() }
}

// Shared access only changes none to present; payload removal requires exclusive access.
pub type OnceCell<T> {
    value: core.cell.UnsafeCell<T?>
}

extend<T> OnceCell<T> {
    pub static const fn new(): OnceCell<T> {
        let empty: T? = none
        OnceCell(core.cell.UnsafeCell.new(empty))
    }

    pub fn get(): (read T from self)? {
        match unsafe { self.value.get_ref() } {
            present(value) => present(read value),
            none => none
        }
    }

    pub mut fn get_mut(): (mut T from self)? {
        self.value.get_mut().as_mut()
    }

    pub fn set(take value: T): Unit throws T {
        if self.get().is_present() { throw value }
        // No callback intervenes; none owns no payload and exposes no live payload view.
        unsafe { *self.value.get() = present(value) }
    }

    pub fn get_or_init<F: take fn(): T>(take initializer: F): read T from self {
        match self.get() {
            present(value) => { return value },
            none => {}
        }
        let value = initializer()
        match capture self.set(value) {
            success(_) => {},
            failure(_) => package.core.panic.panic("reentrant OnceCell initialization")
        }
        match self.get() {
            present(value) => value,
            none => core.intrinsics.abort()
        }
    }

    pub mut fn `take`(): T? { self.value.get_mut().`take`() }

    pub take const fn into_inner(): T? { take self.value.into_inner() }
}

extend<T> OnceCell<T> implements Default {
    static fn default(): OnceCell<T> { OnceCell<T>.new() }
}

extend<T> OnceCell<T> implements From<T> {
    static fn from(take value: T): OnceCell<T> {
        OnceCell(core.cell.UnsafeCell.new(present(value)))
    }
}

extend<T: Clone> OnceCell<T> implements Clone {
    fn clone(): OnceCell<T> {
        match self.get() {
            present(value) => OnceCell(core.cell.UnsafeCell.new(present(value.clone()))),
            none => OnceCell<T>.new()
        }
    }
}

extend<T: PartialEq> OnceCell<T> implements PartialEq {
    fn eq(read other: OnceCell<T>): bool {
        match self.get() {
            present(left) => match other.get() {
                present(right) => left == right,
                none => false
            },
            none => other.get().is_none()
        }
    }
}

extend<T: Eq> OnceCell<T> implements Eq {}

extend<T: fmt.Debug> OnceCell<T> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("OnceCell(")
        match self.get() {
            present(value) => try T.(fmt.Debug).fmt(value, mut f),
            none => try f.write_str("<uninit>")
        }
        try f.write_str(")")
    }
}
