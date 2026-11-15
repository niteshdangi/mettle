// Borrowed lookup keys. `K: KeyView<Q>` says a stored key `K` can lend a
// `read Q` view of itself without allocating or retaining anything, so a
// collection keyed by `K` can be searched with a borrowed `Q` (for example a
// `String` key searched with a `Text`).
//
// Coherence contract: a `Q` view must hash and compare exactly like the `K`
// it came from. Whenever `k.key_view()` and `q` are equal under `Q: Eq`, they
// must feed identical bytes to every `Hasher` (`Q: Hash`); hash collections
// rely on this to find the stored key from the query's hash, and ordered
// collections rely on `Q: Ord` agreeing with `K: Ord`. A type relates to a
// given `Q` at most once; every type relates to itself.
import super.text.Text
import super.clone.Clone

pub interface AsRef<T: unsized> {
    fn as_ref(): read T from self;
}

pub interface Borrow<T: unsized> {
    fn borrow(): read T from self;
}

pub interface AsMut<T: unsized> {
    mut fn as_mut(): mut T from self;
}

pub interface BorrowMut<T: unsized>: Borrow<T> {
    mut fn borrow_mut(): mut T from self;
}

pub interface OwnedType {
    type Owned: Borrow<Self>;
}

pub interface ToOwned: OwnedType {
    fn to_owned(): Self.Owned;
    fn clone_into(mut owned: Self.Owned): Unit {
        owned = self.to_owned()
    }
}

extend<region r, T: AsRef<U> + unsized, U: unsized>
    read T from r implements AsRef<U> {
    fn as_ref(): read U from r {
        T.(AsRef<U>).as_ref(read *self)
    }
}

extend<region r, T: AsRef<U> + unsized, U: unsized>
    mut T from r implements AsRef<U> {
    fn as_ref(): read U from r {
        T.(AsRef<U>).as_ref(read *self)
    }
}

extend<region r, T: AsMut<U> + unsized, U: unsized>
    mut T from r implements AsMut<U> {
    mut fn as_mut(): mut U from r {
        T.(AsMut<U>).as_mut(mut *self)
    }
}

extend<T: unsized> T implements Borrow<T> {
    fn borrow(): read T from self { read self }
}

extend<T: unsized> T implements BorrowMut<T> {
    mut fn borrow_mut(): mut T from self { mut self }
}

extend<T: Clone> T implements OwnedType {
    type Owned = T
}

extend<T: Clone> T implements ToOwned {
    fn to_owned(): T { T.(Clone).clone(self) }
}

pub interface KeyView<Q: unsized> {
    fn key_view(): read Q from self;
}

// Identity: every key is its own view.
extend<T: unsized> T implements KeyView<T> {
    fn key_view(): read T from self { read self }
}
