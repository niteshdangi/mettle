// A raw mutable pointer that is guaranteed not to be null.
pub copy type NonNull<T: unsized> {
    pointer: ptr<mut T>
}

extend<T: unsized> NonNull<T> {
    pub static fn new(pointer: ptr<mut T>): NonNull<T>? {
        if pointer.is_null() { none } else { present(NonNull(pointer)) }
    }

    // Safety: the caller must guarantee `pointer` is non-null.
    pub unsafe static fn new_unchecked(pointer: ptr<mut T>): NonNull<T> {
        NonNull(pointer)
    }

    pub fn as_ptr(): ptr<mut T> { self.pointer }
}

extend<T: unsized> NonNull<T> implements super.clone.Clone {
    fn clone(): NonNull<T> { self }
}
