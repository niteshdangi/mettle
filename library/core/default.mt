// The value a type starts from when nothing more specific is chosen.
// `T.(Default).default()` is explicit and allocates only where the
// implementing type's own constructor does. `@derive(Default)` builds a product
// from the default of each field.

pub interface Default: Sized { static fn default(): Self; }

extend i8 implements Default { static fn default(): i8 { 0i8 } }
extend i16 implements Default { static fn default(): i16 { 0i16 } }
extend i32 implements Default { static fn default(): i32 { 0i32 } }
extend i64 implements Default { static fn default(): i64 { 0i64 } }
extend i128 implements Default { static fn default(): i128 { 0i128 } }
extend isize implements Default { static fn default(): isize { 0isize } }
extend u8 implements Default { static fn default(): u8 { 0u8 } }
extend u16 implements Default { static fn default(): u16 { 0u16 } }
extend u32 implements Default { static fn default(): u32 { 0u32 } }
extend u64 implements Default { static fn default(): u64 { 0u64 } }
extend u128 implements Default { static fn default(): u128 { 0u128 } }
extend usize implements Default { static fn default(): usize { 0usize } }
extend f32 implements Default { static fn default(): f32 { 0.0f32 } }
extend f64 implements Default { static fn default(): f64 { 0.0f64 } }
extend bool implements Default { static fn default(): bool { false } }
extend char implements Default { static fn default(): char { '\0' } }
extend Unit implements Default { static fn default(): Unit { () } }
extend<T> T? implements Default { static fn default(): T? { none } }
extend<A: Default, B: Default> (A, B) implements Default {
    static fn default(): (A, B) { (A.(Default).default(), B.(Default).default()) }
}
extend<A: Default, B: Default, C: Default> (A, B, C) implements Default {
    static fn default(): (A, B, C) {
        (A.(Default).default(), B.(Default).default(), C.(Default).default())
    }
}
