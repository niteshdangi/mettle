// Operator capabilities. The compiler dispatches `a + b`, `a[i]`, `-a`, ... on
// these canonical paths for user types; built-in scalar operators are intrinsic.

pub interface Deref { type Target: unsized; fn deref(): read Self.Target; }
pub interface DerefMut: Deref { mut fn deref_mut(): mut Self.Target; }

pub interface Add<Rhs> { type Output; fn add(read rhs: Rhs): Self.Output; }
pub interface Sub<Rhs> { type Output; fn sub(read rhs: Rhs): Self.Output; }
pub interface Mul<Rhs> { type Output; fn mul(read rhs: Rhs): Self.Output; }
pub interface Div<Rhs> { type Output; fn div(read rhs: Rhs): Self.Output; }
pub interface Rem<Rhs> { type Output; fn rem(read rhs: Rhs): Self.Output; }
pub interface BitAnd<Rhs> { type Output; fn bitand(read rhs: Rhs): Self.Output; }
pub interface BitOr<Rhs> { type Output; fn bitor(read rhs: Rhs): Self.Output; }
pub interface BitXor<Rhs> { type Output; fn bitxor(read rhs: Rhs): Self.Output; }
pub interface Shl<Rhs> { type Output; fn shl(read rhs: Rhs): Self.Output; }
pub interface Shr<Rhs> { type Output; fn shr(read rhs: Rhs): Self.Output; }
pub interface AddAssign<Rhs> { mut fn add_assign(read rhs: Rhs): Unit; }
pub interface SubAssign<Rhs> { mut fn sub_assign(read rhs: Rhs): Unit; }
pub interface MulAssign<Rhs> { mut fn mul_assign(read rhs: Rhs): Unit; }
pub interface DivAssign<Rhs> { mut fn div_assign(read rhs: Rhs): Unit; }
pub interface RemAssign<Rhs> { mut fn rem_assign(read rhs: Rhs): Unit; }
pub interface BitAndAssign<Rhs> { mut fn bitand_assign(read rhs: Rhs): Unit; }
pub interface BitOrAssign<Rhs> { mut fn bitor_assign(read rhs: Rhs): Unit; }
pub interface BitXorAssign<Rhs> { mut fn bitxor_assign(read rhs: Rhs): Unit; }
pub interface ShlAssign<Rhs> { mut fn shl_assign(read rhs: Rhs): Unit; }
pub interface ShrAssign<Rhs> { mut fn shr_assign(read rhs: Rhs): Unit; }
pub interface Neg { type Output; fn neg(): Self.Output; }
pub interface Not { type Output; fn not(): Self.Output; }
pub interface Index<I: unsized> { type Output: unsized; fn index(read index: I): read Self.Output from self; }
pub interface IndexMut<I: unsized> { type Output: unsized; mut fn index_mut(read index: I): mut Self.Output from self; }
pub copy enum RangeEnd { Unbounded, Exclusive(usize), Inclusive(usize) }
pub interface IndexRange { type Output: unsized; fn index_range(start: usize, end: RangeEnd): read Self.Output from self; }
pub interface IndexRangeMut { type Output: unsized; mut fn index_range_mut(start: usize, end: RangeEnd): mut Self.Output from self; }
