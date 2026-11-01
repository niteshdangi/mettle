// Explicit duplication. `clone` produces an independent value of the same
// type; it never aliases the original's resources.
import super.cmp.Ordering

pub interface Clone: Sized {
    fn clone(): Self;
    mut fn clone_from(source: read Self): Unit { self = source.clone() }
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
extend<A: Clone, B: Clone> (A, B) implements Clone {
    fn clone(): (A, B) { (self.0.clone(), self.1.clone()) }
}
extend<T: Clone> T? implements Clone {
    fn clone(): T? {
        match self {
            present(value) => present(value.clone()),
            none => none
        }
    }
}
