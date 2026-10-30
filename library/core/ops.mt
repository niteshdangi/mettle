// Operator capabilities. The compiler dispatches `a + b`, `a[i]`, `-a`, ... on
// these canonical paths for user types; built-in scalar operators are intrinsic.

pub interface Deref { type Target: unsized; fn deref(): read Self::Target; }
pub interface DerefMut { type Target: unsized; mut fn deref_mut(): mut Self::Target; }

pub interface Add<Rhs> { type Output; fn add(rhs: read Rhs): Self::Output; }
pub interface Sub<Rhs> { type Output; fn sub(rhs: read Rhs): Self::Output; }
pub interface Mul<Rhs> { type Output; fn mul(rhs: read Rhs): Self::Output; }
pub interface Div<Rhs> { type Output; fn div(rhs: read Rhs): Self::Output; }
pub interface Rem<Rhs> { type Output; fn rem(rhs: read Rhs): Self::Output; }
pub interface BitAnd<Rhs> { type Output; fn bitand(rhs: read Rhs): Self::Output; }
pub interface BitOr<Rhs> { type Output; fn bitor(rhs: read Rhs): Self::Output; }
pub interface BitXor<Rhs> { type Output; fn bitxor(rhs: read Rhs): Self::Output; }
pub interface Shl<Rhs> { type Output; fn shl(rhs: read Rhs): Self::Output; }
pub interface Shr<Rhs> { type Output; fn shr(rhs: read Rhs): Self::Output; }
pub interface AddAssign<Rhs> { mut fn add_assign(rhs: read Rhs): Unit; }
pub interface SubAssign<Rhs> { mut fn sub_assign(rhs: read Rhs): Unit; }
pub interface MulAssign<Rhs> { mut fn mul_assign(rhs: read Rhs): Unit; }
pub interface DivAssign<Rhs> { mut fn div_assign(rhs: read Rhs): Unit; }
pub interface RemAssign<Rhs> { mut fn rem_assign(rhs: read Rhs): Unit; }
pub interface BitAndAssign<Rhs> { mut fn bitand_assign(rhs: read Rhs): Unit; }
pub interface BitOrAssign<Rhs> { mut fn bitor_assign(rhs: read Rhs): Unit; }
pub interface BitXorAssign<Rhs> { mut fn bitxor_assign(rhs: read Rhs): Unit; }
pub interface ShlAssign<Rhs> { mut fn shl_assign(rhs: read Rhs): Unit; }
pub interface ShrAssign<Rhs> { mut fn shr_assign(rhs: read Rhs): Unit; }
pub interface Neg { type Output; fn neg(): Self::Output; }
pub interface Not { type Output; fn not(): Self::Output; }
pub interface Index<I> { type Output: unsized; fn index(index: read I): read Self::Output from self; }
pub interface IndexMut<I> { type Output: unsized; mut fn index_mut(index: read I): mut Self::Output from self; }
// Range indexing `value[a..b]`, `value[a..]`, `value[..b]`, `value[..=b]`,
// `value[..]` on a non-array, non-slice type: `end` is the exclusive upper
// bound, or usize::MAX when the range has no upper bound.
pub interface IndexRange { type Output: unsized; fn index_range(start: usize, end: usize): read Self::Output from self; }
pub interface IndexRangeMut { type Output: unsized; mut fn index_range_mut(start: usize, end: usize): mut Self::Output from self; }
