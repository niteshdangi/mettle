// Operator capabilities. The compiler dispatches `a + b`, `a[i]`, `-a`, ... on
// these canonical paths for user types; built-in scalar operators are intrinsic.

pub interface FnPtr: Copy {}

pub interface Deref { type Target: unsized; fn deref(): read Self.Target; }
pub interface DerefMut: Deref { mut fn deref_mut(): mut Self.Target; }

pub interface Add<Rhs = Self> { type Output; fn add(read rhs: Rhs): Self.Output; }
pub interface Sub<Rhs = Self> { type Output; fn sub(read rhs: Rhs): Self.Output; }
pub interface Mul<Rhs = Self> { type Output; fn mul(read rhs: Rhs): Self.Output; }
pub interface Div<Rhs = Self> { type Output; fn div(read rhs: Rhs): Self.Output; }
pub interface Rem<Rhs = Self> { type Output; fn rem(read rhs: Rhs): Self.Output; }
pub interface BitAnd<Rhs = Self> { type Output; fn bitand(read rhs: Rhs): Self.Output; }
pub interface BitOr<Rhs = Self> { type Output; fn bitor(read rhs: Rhs): Self.Output; }
pub interface BitXor<Rhs = Self> { type Output; fn bitxor(read rhs: Rhs): Self.Output; }
pub interface Shl<Rhs = Self> { type Output; fn shl(read rhs: Rhs): Self.Output; }
pub interface Shr<Rhs = Self> { type Output; fn shr(read rhs: Rhs): Self.Output; }
pub interface AddAssign<Rhs = Self> { mut fn add_assign(read rhs: Rhs): Unit; }
pub interface SubAssign<Rhs = Self> { mut fn sub_assign(read rhs: Rhs): Unit; }
pub interface MulAssign<Rhs = Self> { mut fn mul_assign(read rhs: Rhs): Unit; }
pub interface DivAssign<Rhs = Self> { mut fn div_assign(read rhs: Rhs): Unit; }
pub interface RemAssign<Rhs = Self> { mut fn rem_assign(read rhs: Rhs): Unit; }
pub interface BitAndAssign<Rhs = Self> { mut fn bitand_assign(read rhs: Rhs): Unit; }
pub interface BitOrAssign<Rhs = Self> { mut fn bitor_assign(read rhs: Rhs): Unit; }
pub interface BitXorAssign<Rhs = Self> { mut fn bitxor_assign(read rhs: Rhs): Unit; }
pub interface ShlAssign<Rhs = Self> { mut fn shl_assign(read rhs: Rhs): Unit; }
pub interface ShrAssign<Rhs = Self> { mut fn shr_assign(read rhs: Rhs): Unit; }
pub interface Neg { type Output; fn neg(): Self.Output; }
pub interface Not { type Output; fn not(): Self.Output; }
pub interface Index<I: unsized> { type Output: unsized; fn index(read index: I): read Self.Output from self; }
pub interface IndexMut<I: unsized> { type Output: unsized; mut fn index_mut(read index: I): mut Self.Output from self; }
pub copy enum RangeEnd { Unbounded, Exclusive(usize), Inclusive(usize) }
pub interface IndexRange { type Output: unsized; fn index_range(start: usize, end: RangeEnd): read Self.Output from self; }
pub interface IndexRangeMut { type Output: unsized; mut fn index_range_mut(start: usize, end: RangeEnd): mut Self.Output from self; }

pub copy enum ControlFlow<B, C = Unit> { Continue(C), Break(B) }
extend<B, C> ControlFlow<B, C> {
    pub const fn is_break(): bool {
        match self { ControlFlow.Break(_) => true, ControlFlow.Continue(_) => false }
    }
    pub const fn is_continue(): bool {
        match self { ControlFlow.Continue(_) => true, ControlFlow.Break(_) => false }
    }
    pub fn as_ref(): (ControlFlow<(read B from self), (read C from self)>) {
        match self {
            ControlFlow.Continue(value) => ControlFlow.Continue(read value),
            ControlFlow.Break(value) => ControlFlow.Break(read value)
        }
    }
    pub mut fn as_mut(): (ControlFlow<(mut B from self), (mut C from self)>) {
        match mut self {
            ControlFlow.Continue(value) => ControlFlow.Continue(mut value),
            ControlFlow.Break(value) => ControlFlow.Break(mut value)
        }
    }
    pub take fn break_value(): B? {
        match take self {
            ControlFlow.Break(value) => present(value),
            ControlFlow.Continue(_) => none
        }
    }
    pub take fn continue_value(): C? {
        match take self {
            ControlFlow.Continue(value) => present(value),
            ControlFlow.Break(_) => none
        }
    }
    pub take fn map_break<U, F: take fn(take B): U>(take f: F): ControlFlow<U, C> {
        match take self {
            ControlFlow.Break(value) => ControlFlow.Break(f(value)),
            ControlFlow.Continue(value) => ControlFlow.Continue(value)
        }
    }
    pub take fn map_continue<U, F: take fn(take C): U>(take f: F): ControlFlow<B, U> {
        match take self {
            ControlFlow.Continue(value) => ControlFlow.Continue(f(value)),
            ControlFlow.Break(value) => ControlFlow.Break(value)
        }
    }
    pub take const fn break_ok(): (Outcome<B, C>) {
        match take self {
            ControlFlow.Break(value) => success(value),
            ControlFlow.Continue(value) => failure(value)
        }
    }
    pub take const fn continue_ok(): (Outcome<C, B>) {
        match take self {
            ControlFlow.Continue(value) => success(value),
            ControlFlow.Break(value) => failure(value)
        }
    }
}
