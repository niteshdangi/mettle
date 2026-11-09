import package.core.clone.Clone
import package.core.convert.From
import super.vec.List

// Slice Cow keeps borrowed reads or an owned Global List.
pub enum Cow<region r, T> {
    Borrowed(read [T] from r);
    Owned(List<T>)
}

extend<region r, T> Cow<region r, T> {
    pub fn is_borrowed(): bool {
        match self {
            Cow.Borrowed(_) => true,
            Cow.Owned(_) => false
        }
    }

    pub fn as_ref(): read [T] from self {
        match self {
            Cow.Borrowed(items) => items,
            Cow.Owned(items) => items.as_slice()
        }
    }
}

extend<region r, T: Clone> Cow<region r, T> {
    pub take fn into_owned(): List<T> {
        match take self {
            Cow.Borrowed(items) => items.to_vec(),
            Cow.Owned(items) => items
        }
    }
}

extend<region r, T: Clone> List<T> implements From<Cow<region r, T>> {
    static fn from(take value: Cow<region r, T>): List<T> {
        value.into_owned()
    }
}
