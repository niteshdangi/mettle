pub import core.borrow.{OwnedType, ToOwned}
import core.borrow.{AsRef, Borrow}
import core.clone.Clone
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.convert.From
import core.fmt.{Debug, Display, Error, Formatter}
import core.ops.Deref
import core.panic.panic
import core.text.Text
import super.alloc.Allocator
import super.vec.List

extend<T> [T] implements OwnedType {
    type Owned = List<T>
}

extend<T: Clone> [T] implements ToOwned {
    fn to_owned(): List<T> { self.to_vec() }
}

pub enum BorrowedOrOwned<region r, B: OwnedType + unsized> {
    Borrowed(read B from r);
    Owned(B.Owned)
}

fn slices_equal<T: PartialEq<U>, U, region r, region s>(
    read left: [T] from r,
    read right: [U] from s
): bool {
    if left.len() != right.len() { return false }
    var index = 0usize
    while index < left.len() {
        if !T.(PartialEq<U>).eq(left[index], right[index]) { return false }
        index += 1usize
    }
    true
}

extend<region r, B: OwnedType + unsized> BorrowedOrOwned<region r, B> {
    pub fn is_borrowed(): bool {
        match self {
            BorrowedOrOwned.Borrowed(_) => true,
            BorrowedOrOwned.Owned(_) => false
        }
    }

    pub fn is_owned(): bool { !self.is_borrowed() }

    pub fn as_ref(): read B from self {
        match self {
            BorrowedOrOwned.Borrowed(value) => value,
            BorrowedOrOwned.Owned(value) => B.Owned.(Borrow<B>).borrow(value)
        }
    }
}

extend<region r, B: ToOwned + unsized> BorrowedOrOwned<region r, B> {
    pub mut fn to_mut(): mut B.Owned from self {
        if self.is_borrowed() {
            let owned = B.(ToOwned).to_owned(self.as_ref())
            self = BorrowedOrOwned<region r, B>.Owned(owned)
        }
        match mut self {
            BorrowedOrOwned.Owned(value) => mut value,
            BorrowedOrOwned.Borrowed(_) => panic("to_mut failed to install an owner")
        }
    }

    pub take fn into_owned(): B.Owned {
        match take self {
            BorrowedOrOwned.Borrowed(value) => B.(ToOwned).to_owned(value),
            BorrowedOrOwned.Owned(value) => value
        }
    }
}

extend<region r, B: OwnedType + unsized> BorrowedOrOwned<region r, B> implements AsRef<B> {
    fn as_ref(): read B from self { self.as_ref() }
}

extend<region r, B: OwnedType + unsized> BorrowedOrOwned<region r, B> implements Borrow<B> {
    fn borrow(): read B from self { self.as_ref() }
}

extend<region r, T: Clone + PartialEq<U>, U>
    BorrowedOrOwned<region r, [T]> implements PartialEq<[U]> {
    fn eq(read other: [U]): bool {
        [T].(PartialEq<[U]>).eq(self.as_ref(), read other)
    }
}

extend<region r> Text implements PartialEq<BorrowedOrOwned<region r, Text>> {
    fn eq(read other: BorrowedOrOwned<region r, Text>): bool {
        Text.(PartialEq).eq(self, other.as_ref())
    }
}

extend<region r, region s> read Text from r
    implements PartialEq<BorrowedOrOwned<region s, Text>> {
    fn eq(read other: BorrowedOrOwned<region s, Text>): bool {
        Text.(PartialEq).eq(*self, other.as_ref())
    }
}

extend<region r, B: OwnedType + unsized> BorrowedOrOwned<region r, B> implements Deref {
    type Target = B
    fn deref(): read B from self { self.as_ref() }
}

extend<region r, B: ToOwned + unsized> BorrowedOrOwned<region r, B> implements Clone {
    fn clone(): BorrowedOrOwned<region r, B> {
        match self {
            BorrowedOrOwned.Borrowed(value) => BorrowedOrOwned.Borrowed(value),
            BorrowedOrOwned.Owned(value) => BorrowedOrOwned.Owned(B.(ToOwned).to_owned(B.Owned.(Borrow<B>).borrow(value)))
        }
    }
}

extend<region r, B: Debug + OwnedType + unsized> BorrowedOrOwned<region r, B> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error { try self.as_ref().fmt(mut f) }
}

extend<region r, B: Display + OwnedType + unsized> BorrowedOrOwned<region r, B> implements Display {
    fn fmt(mut f: Formatter): Unit throws Error { try self.as_ref().fmt(mut f) }
}

extend<region r, B: OwnedType + PartialEq<C> + unsized, C: OwnedType + unsized, region s>
    BorrowedOrOwned<region r, B> implements PartialEq<BorrowedOrOwned<region s, C>> {
    fn eq(read other: BorrowedOrOwned<region s, C>): bool {
        self.as_ref() == other.as_ref()
    }
}

extend<region r, B: Eq + OwnedType + unsized> BorrowedOrOwned<region r, B> implements Eq {}

extend<region r, B: Ord + OwnedType + unsized> BorrowedOrOwned<region r, B> implements Ord {
    fn cmp(read other: BorrowedOrOwned<region r, B>): Ordering {
        self.as_ref().cmp(other.as_ref())
    }
}

extend<region r, B: OwnedType + PartialOrd<C> + unsized, C: OwnedType + unsized, region s>
    BorrowedOrOwned<region r, B> implements PartialOrd<BorrowedOrOwned<region s, C>> {
    fn partial_cmp(read other: BorrowedOrOwned<region s, C>): Ordering? {
        self.as_ref().partial_cmp(other.as_ref())
    }
}

extend<region r> BorrowedOrOwned<region r, Text> implements PartialEq<Text> {
    fn eq(read other: Text): bool { self.as_ref() == other }
}

extend<region r, region s> BorrowedOrOwned<region r, Text> implements PartialEq<read Text from s> {
    fn eq(read other: read Text from s): bool { self.as_ref() == *other }
}

extend<region r, T: Clone + PartialEq<U>, U, region s>
    BorrowedOrOwned<region r, [T]> implements PartialEq<read [U] from s> {
    fn eq(read other: read [U] from s): bool {
        slices_equal(self.as_ref(), *other)
    }
}

extend<region r, T: Clone + PartialEq<U>, U, region s>
    BorrowedOrOwned<region r, [T]> implements PartialEq<mut [U] from s> {
    fn eq(read other: mut [U] from s): bool {
        slices_equal(self.as_ref(), read *other)
    }
}

extend<region r, T: Clone + PartialEq<U>, U, A: super.alloc.Allocator>
    BorrowedOrOwned<region r, [T]> implements PartialEq<List<U, A>> {
    fn eq(read other: List<U, A>): bool {
        slices_equal(self.as_ref(), other.as_slice())
    }
}

extend<region r, B: OwnedType + unsized> BorrowedOrOwned<region r, B> implements From<read B from r> {
    static fn from(take value: read B from r): BorrowedOrOwned<region r, B> {
        BorrowedOrOwned<region r, B>.Borrowed(value)
    }
}

extend<region r, B: OwnedType + unsized> BorrowedOrOwned<region r, B> implements From<B.Owned> {
    static fn from(take value: B.Owned): BorrowedOrOwned<region r, B> {
        BorrowedOrOwned<region r, B>.Owned(value)
    }
}

extend<region r, B: OwnedType + unsized> BorrowedOrOwned<region r, B>
    implements From<read B.Owned from r> {
    static fn from(take value: read B.Owned from r): BorrowedOrOwned<region r, B> {
        BorrowedOrOwned<region r, B>.Borrowed(B.Owned.(Borrow<B>).borrow(value))
    }
}

extend<region r, T: Clone, const N: usize>
    BorrowedOrOwned<region r, [T]> implements From<read [T; N] from r> {
    static fn from(take value: read [T; N] from r): BorrowedOrOwned<region r, [T]> {
        BorrowedOrOwned<region r, [T]>.Borrowed(value)
    }
}

extend<region r, T: Clone> List<T> implements From<BorrowedOrOwned<region r, [T]>> {
    static fn from(take value: BorrowedOrOwned<region r, [T]>): List<T> {
        value.into_owned()
    }
}
