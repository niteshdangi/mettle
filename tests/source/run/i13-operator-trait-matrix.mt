// profiles: debug release
import core.ops.{Add, AddAssign, BitAnd, BitAndAssign, BitOr, BitOrAssign, BitXor, BitXorAssign}
import core.ops.{Deref, DerefMut, Div, DivAssign, Index, IndexMut, Mul, MulAssign, Neg, Not}
import core.ops.{Rem, RemAssign, Shl, ShlAssign, Shr, ShrAssign, Sub, SubAssign}

type Bits { value: i32 }

extend Bits implements Add<Bits> { type Output = Bits; fn add(read rhs: Bits): Bits { Bits(self.value + rhs.value) } }
extend Bits implements Sub<Bits> { type Output = Bits; fn sub(read rhs: Bits): Bits { Bits(self.value - rhs.value) } }
extend Bits implements Mul<Bits> { type Output = Bits; fn mul(read rhs: Bits): Bits { Bits(self.value * rhs.value) } }
extend Bits implements Div<Bits> { type Output = Bits; fn div(read rhs: Bits): Bits { Bits(self.value / rhs.value) } }
extend Bits implements Rem<Bits> { type Output = Bits; fn rem(read rhs: Bits): Bits { Bits(self.value % rhs.value) } }
extend Bits implements BitAnd<Bits> { type Output = Bits; fn bitand(read rhs: Bits): Bits { Bits(self.value & rhs.value) } }
extend Bits implements BitOr<Bits> { type Output = Bits; fn bitor(read rhs: Bits): Bits { Bits(self.value | rhs.value) } }
extend Bits implements BitXor<Bits> { type Output = Bits; fn bitxor(read rhs: Bits): Bits { Bits(self.value ^ rhs.value) } }
extend Bits implements Shl<i32> { type Output = Bits; fn shl(read rhs: i32): Bits { Bits(self.value << rhs) } }
extend Bits implements Shr<i32> { type Output = Bits; fn shr(read rhs: i32): Bits { Bits(self.value >> rhs) } }
extend Bits implements Neg { type Output = Bits; fn neg(): Bits { Bits(0 - self.value) } }
extend Bits implements Not { type Output = Bits; fn not(): Bits { Bits(!self.value) } }
extend Bits implements AddAssign<Bits> { mut fn add_assign(read rhs: Bits): Unit { self.value += rhs.value } }
extend Bits implements SubAssign<Bits> { mut fn sub_assign(read rhs: Bits): Unit { self.value -= rhs.value } }
extend Bits implements MulAssign<Bits> { mut fn mul_assign(read rhs: Bits): Unit { self.value *= rhs.value } }
extend Bits implements DivAssign<Bits> { mut fn div_assign(read rhs: Bits): Unit { self.value /= rhs.value } }
extend Bits implements RemAssign<Bits> { mut fn rem_assign(read rhs: Bits): Unit { self.value %= rhs.value } }
extend Bits implements BitAndAssign<Bits> { mut fn bitand_assign(read rhs: Bits): Unit { self.value &= rhs.value } }
extend Bits implements BitOrAssign<Bits> { mut fn bitor_assign(read rhs: Bits): Unit { self.value |= rhs.value } }
extend Bits implements BitXorAssign<Bits> { mut fn bitxor_assign(read rhs: Bits): Unit { self.value ^= rhs.value } }
extend Bits implements ShlAssign<i32> { mut fn shl_assign(read rhs: i32): Unit { self.value <<= rhs } }
extend Bits implements ShrAssign<i32> { mut fn shr_assign(read rhs: i32): Unit { self.value >>= rhs } }

type Slot { items: [i32; 2] }
extend Slot implements Index<usize> {
    type Output = i32
    fn index(read position: usize): read i32 from self { read self.items[position] }
}
extend Slot implements IndexMut<usize> {
    type Output = i32
    mut fn index_mut(read position: usize): mut i32 from self { mut self.items[position] }
}

type Holder { inner: Bits }
extend Holder implements Deref {
    type Target = Bits
    fn deref(): read Bits from self { read self.inner }
}
extend Holder implements DerefMut {
    mut fn deref_mut(): mut Bits from self { mut self.inner }
}

type Tracked {
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

fn applied<T: Add<T, Output = T> + Sub<T, Output = T>>(read left: T, read right: T): T {
    T.(Sub<T>).sub(T.(Add<T>).add(left, right), right)
}

fn main(): i32 {
    let six = Bits(6)
    let three = Bits(3)
    if (six + three).value != 9 || (six - three).value != 3 || (six * three).value != 18 { return 1 }
    if (six / three).value != 2 || (six % Bits(4)).value != 2 { return 2 }
    if (six & three).value != 2 || (six | three).value != 7 || (six ^ three).value != 5 { return 3 }
    if (six << 2).value != 24 || (six >> 1).value != 3 || (-six).value != -6 || (!six).value != -7 { return 4 }
    if applied(six, three).value != 6 { return 5 }

    var acc = Bits(6)
    acc += three
    acc -= Bits(1)
    acc *= Bits(2)
    acc /= Bits(4)
    acc %= Bits(3)
    if acc.value != 1 { return 6 }
    acc |= Bits(6)
    acc &= Bits(5)
    acc ^= Bits(1)
    acc <<= 3
    acc >>= 1
    if acc.value != 16 { return 7 }

    var slot = Slot([1, 2])
    slot[1usize] = 5
    if slot[1usize] != 5 || slot[0usize] != 1 { return 8 }
    var holder = Holder(Bits(2))
    Holder.(DerefMut).deref_mut(mut holder).value += 1
    if Holder.(Deref).deref(holder).value != 3 { return 9 }

    var counts = [0i32]
    {
        let counter = Tracked(counts.as_mut_ptr())
    }
    if counts[0usize] != 1 { return 10 }
    0
}
