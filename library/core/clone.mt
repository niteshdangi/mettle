// Explicit duplication. `clone` produces an independent value of the same
// type; it never aliases the original's resources.
import super::cmp::Ordering;

pub interface Clone: Sized { fn clone(): Self; }

impl i8 implements Clone { fn clone(): i8 { self } }
impl i16 implements Clone { fn clone(): i16 { self } }
impl i32 implements Clone { fn clone(): i32 { self } }
impl i64 implements Clone { fn clone(): i64 { self } }
impl isize implements Clone { fn clone(): isize { self } }
impl u8 implements Clone { fn clone(): u8 { self } }
impl u16 implements Clone { fn clone(): u16 { self } }
impl u32 implements Clone { fn clone(): u32 { self } }
impl u64 implements Clone { fn clone(): u64 { self } }
impl usize implements Clone { fn clone(): usize { self } }
impl bool implements Clone { fn clone(): bool { self } }
impl char implements Clone { fn clone(): char { self } }
impl Unit implements Clone { fn clone(): Unit { self } }
impl Ordering implements Clone { fn clone(): Ordering { self } }
impl<A: Clone, B: Clone> (A, B) implements Clone {
    fn clone(): (A, B) { (self.0.clone(), self.1.clone()) }
}
impl<T: Clone> T? implements Clone {
    fn clone(): T? {
        match self {
            present(value) => present(value.clone()),
            none => none
        }
    }
}
