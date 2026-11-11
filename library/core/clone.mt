// Explicit duplication. `clone` produces an independent value of the same
// type; it never aliases the original's resources.
import super.cmp.Ordering
import super.slice.drop_values

pub interface Clone: Sized {
    fn clone(): Self;
    mut fn clone_from(read source: Self): Unit { self = source.clone() }
}

extend i8 implements Clone { fn clone(): i8 { self } }
extend i16 implements Clone { fn clone(): i16 { self } }
extend i32 implements Clone { fn clone(): i32 { self } }
extend i64 implements Clone { fn clone(): i64 { self } }
extend i128 implements Clone { fn clone(): i128 { self } }
extend isize implements Clone { fn clone(): isize { self } }
extend u8 implements Clone { fn clone(): u8 { self } }
extend u16 implements Clone { fn clone(): u16 { self } }
extend u32 implements Clone { fn clone(): u32 { self } }
extend u64 implements Clone { fn clone(): u64 { self } }
extend u128 implements Clone { fn clone(): u128 { self } }
extend usize implements Clone { fn clone(): usize { self } }
extend f32 implements Clone { fn clone(): f32 { self } }
extend f64 implements Clone { fn clone(): f64 { self } }
extend bool implements Clone { fn clone(): bool { self } }
extend char implements Clone { fn clone(): char { self } }
extend Unit implements Clone { fn clone(): Unit { self } }
extend Ordering implements Clone { fn clone(): Ordering { self } }
// Tuples clone field by field, at every arity up to twelve.
macro tuple_clone {
    ($($name:ident => $field:literal),*) => {
        extend<$($name: Clone),*> ($($name,)*) implements Clone {
            fn clone(): ($($name,)*) { ($(self.$field.clone(),)*) }
        }
    };
}

tuple_clone!(A => 0)
tuple_clone!(A => 0, B => 1)
tuple_clone!(A => 0, B => 1, C => 2)
tuple_clone!(A => 0, B => 1, C => 2, D => 3)
tuple_clone!(A => 0, B => 1, C => 2, D => 3, E => 4)
tuple_clone!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5)
tuple_clone!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, G => 6)
tuple_clone!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, G => 6, H => 7)
tuple_clone!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, G => 6, H => 7, I => 8)
tuple_clone!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, G => 6, H => 7, I => 8, J => 9)
tuple_clone!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, G => 6, H => 7, I => 8, J => 9, K => 10)
tuple_clone!(A => 0, B => 1, C => 2, D => 3, E => 4, F => 5, G => 6, H => 7, I => 8, J => 9, K => 10, L => 11)

extend<T: Clone, E: Clone> (Outcome<T, E>) implements Clone {
    fn clone(): (Outcome<T, E>) {
        match self {
            success(value) => success(value.clone()),
            failure(error) => failure(error.clone())
        }
    }
}
extend<T: Clone> T? implements Clone {
    fn clone(): T? {
        match self {
            present(value) => present(value.clone()),
            none => none
        }
    }
}
pub(super) type ArrayInit<T, const N: usize> {
    storage: core.mem.MaybeUninit<[T; N]>
    initialized: usize
    drop {
        let initialized = self.initialized
        self.initialized = 0usize
        // Safety: only the still-owned initialized prefix is destroyed.
        unsafe {
            drop_values(self.storage.as_mut_ptr().cast<T>(), initialized)
        }
    }
}

extend<T, const N: usize> ArrayInit<T, N> {
    pub(super) static fn new(): ArrayInit<T, N> {
        ArrayInit(core.mem.MaybeUninit<[T; N]>.uninit(), 0usize)
    }
    pub(super) mut fn push(take value: T): Unit {
        if self.initialized == N { super.panic.panic("array is already initialized") }
        // Safety: this is the next in-bounds uninitialized slot.
        unsafe {
            core.ptr.write(
                self.storage.as_mut_ptr().cast<T>().add(self.initialized),
                value
            )
        }
        self.initialized += 1usize
    }
    pub(super) take fn finish(): [T; N] {
        var guard = self
        if guard.initialized != N { super.panic.panic("array is not initialized") }
        guard.initialized = 0usize
        // Safety: the complete array transfers out and the guard owns no elements.
        unsafe { core.ptr.`read`(guard.storage.as_ptr()) }
    }
}

extend<T: Clone, const N: usize> [T; N] implements Clone {
    fn clone(): [T; N] {
        var result = ArrayInit<T, N>.new()
        var i = 0usize
        while i < N {
            result.push(self[i].clone())
            i += 1usize
        }
        result.finish()
    }
}
