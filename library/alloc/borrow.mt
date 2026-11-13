pub import core.borrow.{OwnedType, ToOwned}
import core.borrow.{AsRef, Borrow}
import core.clone.Clone
import core.convert.From
import core.ops.Deref
import core.panic.panic
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
            let owned = self.as_ref().to_owned()
            self = BorrowedOrOwned<region r, B>.Owned(owned)
        }
        match mut self {
            BorrowedOrOwned.Owned(value) => mut value,
            BorrowedOrOwned.Borrowed(_) => panic("to_mut failed to install an owner")
        }
    }

    pub take fn into_owned(): B.Owned {
        match take self {
            BorrowedOrOwned.Borrowed(value) => value.to_owned(),
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

extend<region r, B: OwnedType + unsized> BorrowedOrOwned<region r, B> implements Deref {
    type Target = B
    fn deref(): read B from self { self.as_ref() }
}

extend<region r, B: ToOwned + unsized> BorrowedOrOwned<region r, B> implements Clone {
    fn clone(): BorrowedOrOwned<region r, B> {
        match self {
            BorrowedOrOwned.Borrowed(value) => BorrowedOrOwned.Borrowed(value),
            BorrowedOrOwned.Owned(value) => BorrowedOrOwned.Owned(B.Owned.(Borrow<B>).borrow(value).to_owned())
        }
    }
}

extend<region r, T: Clone> List<T> implements From<BorrowedOrOwned<region r, [T]>> {
    static fn from(take value: BorrowedOrOwned<region r, [T]>): List<T> {
        value.into_owned()
    }
}
