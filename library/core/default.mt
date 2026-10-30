// The value a type starts from when nothing more specific is chosen.
// `<T implements Default>::default()` is explicit and allocates only where the
// implementing type's own constructor does. `@derive(Default)` builds a product
// from the default of each field.

pub interface Default: Sized { static fn default(): Self; }

impl i8 implements Default { static fn default(): i8 { 0i8 } }
impl i16 implements Default { static fn default(): i16 { 0i16 } }
impl i32 implements Default { static fn default(): i32 { 0i32 } }
impl i64 implements Default { static fn default(): i64 { 0i64 } }
impl isize implements Default { static fn default(): isize { 0isize } }
impl u8 implements Default { static fn default(): u8 { 0u8 } }
impl u16 implements Default { static fn default(): u16 { 0u16 } }
impl u32 implements Default { static fn default(): u32 { 0u32 } }
impl u64 implements Default { static fn default(): u64 { 0u64 } }
impl usize implements Default { static fn default(): usize { 0usize } }
impl f32 implements Default { static fn default(): f32 { 0.0f32 } }
impl f64 implements Default { static fn default(): f64 { 0.0f64 } }
impl bool implements Default { static fn default(): bool { false } }
impl char implements Default { static fn default(): char { '\0' } }
impl Unit implements Default { static fn default(): Unit { () } }
impl<T> T? implements Default { static fn default(): T? { none } }
impl<A: Default, B: Default> (A, B) implements Default {
    static fn default(): (A, B) { (<A implements Default>::default(), <B implements Default>::default()) }
}
impl<A: Default, B: Default, C: Default> (A, B, C) implements Default {
    static fn default(): (A, B, C) {
        (<A implements Default>::default(), <B implements Default>::default(), <C implements Default>::default())
    }
}
