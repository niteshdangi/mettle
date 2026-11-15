// Runtime identity for static types. Identity values are not stable between runs.

import super.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import super.clone.Clone
import super.fmt.{Debug, Error, Formatter, Write}
import super.hash.{Hash, Hasher}
import super.text.Text

pub copy type TypeId { value: u64 }

pub const fn type_id<T: Static + unsized>(): TypeId { TypeId(core.intrinsics.type_id<T>()) }

extend TypeId {
    pub static const fn of<T: Static + unsized>(): TypeId { type_id<T>() }
}
extend TypeId implements PartialEq {
    fn eq(read other: TypeId): bool { self.value == other.value }
}
extend TypeId implements Eq {}
extend TypeId implements PartialOrd {
    fn partial_cmp(read other: TypeId): Ordering? {
        present(self.value.cmp(read other.value))
    }
}
extend TypeId implements Ord {
    fn cmp(read other: TypeId): Ordering {
        self.value.cmp(read other.value)
    }
}
extend TypeId implements Clone {
    fn clone(): TypeId { self }
}
extend TypeId implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        self.value.hash(mut state)
    }
}
extend TypeId implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        var tuple = try f.debug_tuple("TypeId")
        try tuple.field(self.value)
        try tuple.finish()
    }
}

// Diagnostic text only; spelling is target- and compiler-dependent.
pub fn type_name<T: unsized>(): read Text from static {
    core.intrinsics.type_name<T>()
}

pub fn type_name_of_val<T: unsized>(read value: T): read Text from static {
    type_name<T>()
}

// Reports the identity of a value's static type.
pub interface Any: Static {
    fn type_id(): TypeId;
}
extend<T: Static + unsized> T implements Any {
    fn type_id(): TypeId { type_id<T>() }
}
extend<region r> any Any from r implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("Any { .. }")
    }
}

// Compares `T` with the dynamic type of `value`: the type it was erased from.
pub fn is<region r, T: Static>(read value: any Any from r): bool { value.is<T>() }

extend<region r> read any Any from r {
    pub fn is<T: Static>(): bool { self.type_id() == type_id<T>() }

    pub fn downcast_ref<T: Static>(): (read T from r)? {
        if !self.is<T>() { return none }
        let same = core.ptr.from_ref(self).cast<T>()
        present(unsafe { read *same })
    }
}

extend<region r> mut any Any from r {
    pub mut fn downcast_mut<T: Static>(): (mut T from r)? {
        if !is<T>(read self) { return none }
        let same = core.ptr.from_mut(self).cast<T>()
        present(unsafe { mut *same })
    }
}

// Reinterprets `value` as a `T` when its dynamic type is `T`.
pub fn downcast_ref<region r, T: Static>(
    read value: any Any from r
): (read T from r)? {
    value.downcast_ref<T>()
}

pub fn downcast_mut<region r, T: Static>(
    mut value: any Any from r
): (mut T from r)? {
    value.downcast_mut<T>()
}
