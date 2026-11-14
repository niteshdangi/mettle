import super.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import super.clone.Clone
import super.default.Default
import super.fmt.{Debug, Error, Formatter}
import super.hash.{Hash, Hasher}
import super.slice.SliceIterMut
import super.slice.SliceChunksMut
import super.slice.SliceChunksExactMut
import super.slice.SliceRChunksMut
import super.slice.SliceRChunksExactMut
import super.slice.SliceSplitMut
import super.slice.SliceChunkByMut

pub interface Unpin {}
pub interface UnwindSafe {}
pub interface RefUnwindSafe {}

extend PhantomPinned implements Clone {
    fn clone(): PhantomPinned { self }
}
extend PhantomPinned implements PartialEq {
    fn eq(read other: PhantomPinned): bool { true }
}
extend PhantomPinned implements Eq {}
extend PhantomPinned implements PartialOrd {
    fn partial_cmp(read other: PhantomPinned): Ordering? { present(Ordering.Equal) }
}
extend PhantomPinned implements Ord {
    fn cmp(read other: PhantomPinned): Ordering { Ordering.Equal }
}
extend PhantomPinned implements Default {
    static fn default(): PhantomPinned { PhantomPinned }
}
extend PhantomPinned implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {}
}
extend PhantomPinned implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("PhantomPinned")
    }
}

unsafe extend<region r, T: RefUnwindSafe> SliceIterMut<region r, T> implements RefUnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe> SliceChunksMut<region r, T> implements RefUnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe> SliceChunksExactMut<region r, T> implements RefUnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe> SliceRChunksMut<region r, T> implements RefUnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe> SliceRChunksExactMut<region r, T> implements RefUnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe, F: RefUnwindSafe> SliceSplitMut<region r, T, F> implements RefUnwindSafe {}
unsafe extend<region r, T: RefUnwindSafe, F: RefUnwindSafe> SliceChunkByMut<region r, T, F> implements RefUnwindSafe {}

pub copy type PhantomData<T: unsized> {}

extend<T: unsized> PhantomData<T> implements Clone {
    fn clone(): PhantomData<T> { self }
}
extend<T: unsized> PhantomData<T> implements PartialEq {
    fn eq(read other: PhantomData<T>): bool { true }
}
extend<T: unsized> PhantomData<T> implements Eq {}
extend<T: unsized> PhantomData<T> implements PartialOrd {
    fn partial_cmp(read other: PhantomData<T>): Ordering? { present(Ordering.Equal) }
}
extend<T: unsized> PhantomData<T> implements Ord {
    fn cmp(read other: PhantomData<T>): Ordering { Ordering.Equal }
}
extend<T: unsized> PhantomData<T> implements Default {
    static fn default(): PhantomData<T> { PhantomData<T>() }
}
extend<T: unsized> PhantomData<T> implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {}
}
extend<T: unsized> PhantomData<T> implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("PhantomData")
    }
}
