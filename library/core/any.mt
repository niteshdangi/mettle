// Runtime type identity. `type_id` is a compiler intrinsic: equal types have
// equal identities in every package; distinct types differ (up to a 64-bit
// hash collision of their canonical names).

import super.cmp.{Eq, PartialEq};

pub copy type TypeId { value: u64 }

extend TypeId implements PartialEq {
    fn eq(other: read TypeId): bool { self.value == other.value }
}
extend TypeId implements Eq {}

pub fn type_id<T>(): TypeId { TypeId(core.intrinsics.type_id<T>()) }

// Reports the identity of a value's static type.
pub interface Any {
    fn type_id(): TypeId;
}
extend<T> T implements Any {
    fn type_id(): TypeId { type_id<T>() }
}

pub fn is<T, U>(value: read U): bool { type_id<T>() == type_id<U>() }

// Reinterprets `value` as a `T` when both are the same type.
pub fn downcast_ref<T, U>(value: read U): (read T from value)? {
    if type_id<T>() != type_id<U>() { return none }
    let pointer = core.ptr.from_ref(value)
    let same = unsafe { core.mem.transmute<ptr<read T>>(pointer) }
    present(unsafe { read *same })
}

pub fn downcast_mut<T, U>(value: mut U): (mut T from value)? {
    if type_id<T>() != type_id<U>() { return none }
    let pointer = core.ptr.from_mut(value)
    let same = unsafe { core.mem.transmute<ptr<mut T>>(pointer) }
    present(unsafe { mut *same })
}
