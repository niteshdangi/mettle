import package.core.clone.Clone
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.convert.From
import package.core.default.Default
import package.core.fmt
import package.core.ops.{Deref, DerefMut}

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

extend<T: PartialEq> core.cell.RefCell<T> implements PartialEq {
    fn eq(read other: core.cell.RefCell<T>): bool {
        let left = self.borrow()
        let right = other.borrow()
        left.get_ref().eq(right.get_ref())
    }
}

extend<T: Eq> core.cell.RefCell<T> implements Eq {}

extend<T: PartialOrd> core.cell.RefCell<T> implements PartialOrd {
    fn partial_cmp(read other: core.cell.RefCell<T>): Ordering? {
        let left = self.borrow()
        let right = other.borrow()
        left.get_ref().partial_cmp(right.get_ref())
    }
}

extend<T: Ord> core.cell.RefCell<T> implements Ord {
    fn cmp(read other: core.cell.RefCell<T>): Ordering {
        let left = self.borrow()
        let right = other.borrow()
        left.get_ref().cmp(right.get_ref())
    }
}

extend<T: fmt.Debug> core.cell.RefCell<T> implements fmt.Debug {
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

extend<T: fmt.Debug> core.cell.Ref<T> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.get_ref(), mut f)
    }
}

extend<T: fmt.Display> core.cell.Ref<T> implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Display).fmt(self.get_ref(), mut f)
    }
}

extend<T: fmt.Debug> core.cell.RefMut<T> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try T.(fmt.Debug).fmt(self.get_ref(), mut f)
    }
}

extend<T: fmt.Display> core.cell.RefMut<T> implements fmt.Display {
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
