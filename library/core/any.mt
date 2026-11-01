// Runtime identity for static types. Identity values are not stable between runs.

import super.cmp.{Eq, PartialEq}

pub copy type TypeId { value: u64 }

extend TypeId implements PartialEq {
    fn eq(other: read TypeId): bool { self.value == other.value }
}
extend TypeId implements Eq {}

pub fn type_id<T: Static + unsized>(): TypeId { TypeId(core.intrinsics.type_id<T>()) }

// Reports the identity of a value's static type.
pub interface Any: Static {
    fn type_id(): TypeId;
}
extend<T: Static + unsized> T implements Any {
    fn type_id(): TypeId { type_id<T>() }
}

// Compares `T` with the dynamic type of `value`: the type it was erased from.
pub fn is<T: Static>(value: read any Any): bool { value.type_id() == type_id<T>() }

// Reinterprets `value` as a `T` when its dynamic type is `T`.
pub fn downcast_ref<T: Static>(value: read any Any): (read T from value)? {
    if !is<T>(value) { return none }
    let same = core.ptr.from_ref(value).cast<T>()
    present(unsafe { read *same })
}

pub fn downcast_mut<T: Static>(value: mut any Any): (mut T from value)? {
    if !is<T>(read value) { return none }
    let same = core.ptr.from_mut(value).cast<T>()
    present(unsafe { mut *same })
}
