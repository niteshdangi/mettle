import package.core.borrow.{AsMut, AsRef, Borrow, BorrowMut}
import package.core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import package.core.convert.From
import package.core.error.Error
import package.core.fmt
import package.core.hash.{Hash, Hasher}
import package.core.iter.{BidirectionalIterator, ExactSizeIterator, FusedIterator}
import package.core.iter.{FromItems, Iterable, Iterator, MutableIterable, OwnedIterable}
import package.core.ops.{Deref, DerefMut}
import package.core.future.{Future, Context, Poll}
import super.alloc.{Allocator, Global, AllocError, Layout, layout_of, layout_of_val, layout_array, layout_unchecked, free_block, handle_alloc_error}
import package.core.clone.Clone
import package.core.default.Default
import package.core.slice.{SliceIter, SliceIterMut, drop_values}
import package.core.text.Text
import super.vec.slice_ptr_mut
import super.vec.slice_ptr

// Unique owner of one heap value, tied to the allocator that produced it.
pub type Box<T: unsized, A: Allocator = super.alloc.Global> {
    p: ptr<mut T>
    a: A
    drop {
        let _free = unsafe { free_block(self.p.cast<u8>(), layout_of_val(self.get()), core.ptr.from_mut(self.a)) }
        unsafe { core.ptr.drop_in_place(self.p) }
    }
}

// Owns the exact Box<[T]> allocation. Values in [front, back) remain
// initialized and iterator-owned; moved-out elements are outside that range.
pub type BoxSliceIntoIter<T, A: Allocator = Global> {
    p: ptr<mut T>
    front: usize
    back: usize
    layout: Layout
    a: A
    drop {
        let _free = unsafe { free_block(self.p.cast<u8>(), self.layout, core.ptr.from_mut(self.a)) }
        if self.front < self.back {
            // The guard advances before each destructor, so unwinding cannot
            // revisit an element; `_free` releases the allocation afterward.
            unsafe { drop_values(self.p.add(self.front), self.back - self.front) }
        }
    }
}

pub fn try_new_in<T, A: Allocator>(value: take T, allocator: take A): Box<T, A> throws AllocError {
    var a = allocator
    let raw = try a.allocate(layout_of<T>())
    unsafe { core.ptr.write(raw.cast<T>(), value) }
    Box(raw.cast<T>(), a)
}

pub fn new_in<T, A: Allocator>(value: take T, allocator: take A): Box<T, A> {
    let outcome = capture try_new_in(value, allocator)
    match take outcome {
        success(b) => b,
        failure(e) => handle_alloc_error(layout_of<T>())
    }
}

pub fn try_new<T>(value: take T): Box<T> throws AllocError { try try_new_in(value, Global()) }
pub fn new<T>(value: take T): Box<T> { new_in(value, Global()) }

fn uninit_slice_layout<T>(len: usize): Layout throws AllocError {
    let result = capture layout_array<core.mem.MaybeUninit<T>>(len)
    match take result {
        success(layout) => layout,
        failure(error) => throw AllocError(error.size, error.align)
    }
}

fn try_new_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A,
    zeroed: bool
): Box<[core.mem.MaybeUninit<T>], A> throws AllocError {
    var a = allocator
    let layout = try uninit_slice_layout<T>(len)
    let raw = try a.allocate(layout)
    if zeroed && layout.size() != 0usize {
        // `raw` is writable for exactly `layout.size()` bytes; MaybeUninit
        // accepts every bit pattern, and no element is exposed as initialized.
        unsafe { core.ptr.write_bytes(raw, 0u8, layout.size()) }
    }
    let slice = slice_ptr_mut(raw.cast<core.mem.MaybeUninit<T>>(), len)
    Box(slice, a)
}

pub fn try_new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Box<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try try_new_slice_in<T, A>(len, allocator, false)
}

pub fn new_uninit_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Box<[core.mem.MaybeUninit<T>], A> {
    let result = capture try_new_uninit_slice_in<T, A>(len, allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe {
            layout_unchecked(error.size, error.align)
        })
    }
}

pub fn try_new_uninit_slice<T>(
    len: usize
): Box<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_uninit_slice_in<T, Global>(len, Global())
}

pub fn new_uninit_slice<T>(len: usize): Box<[core.mem.MaybeUninit<T>]> {
    new_uninit_slice_in<T, Global>(len, Global())
}

pub fn try_new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Box<[core.mem.MaybeUninit<T>], A> throws AllocError {
    try try_new_slice_in<T, A>(len, allocator, true)
}

pub fn new_zeroed_slice_in<T, A: Allocator>(
    len: usize,
    allocator: take A
): Box<[core.mem.MaybeUninit<T>], A> {
    let result = capture try_new_zeroed_slice_in<T, A>(len, allocator)
    match take result {
        success(owner) => owner,
        failure(error) => handle_alloc_error(unsafe {
            layout_unchecked(error.size, error.align)
        })
    }
}

pub fn try_new_zeroed_slice<T>(
    len: usize
): Box<[core.mem.MaybeUninit<T>]> throws AllocError {
    try try_new_zeroed_slice_in<T, Global>(len, Global())
}

pub fn new_zeroed_slice<T>(len: usize): Box<[core.mem.MaybeUninit<T>]> {
    new_zeroed_slice_in<T, Global>(len, Global())
}

// Copies a validated Text into an exact-sized Box-owned UTF-8 allocation.
pub fn try_copy_text_in<A: Allocator>(
    value: read Text,
    allocator: take A
): Box<Text, A> throws AllocError {
    var a = allocator
    let bytes = value.as_bytes()
    let layout = layout_of_val(bytes)
    let raw = try a.allocate(layout)
    let data = raw.cast<u8>()
    // Text is validated and the allocation covers its complete byte extent.
    unsafe {
        core.ptr.copy(package.core.slice.data(bytes), data, bytes.len())
    }
    let slice = slice_ptr_mut(data, bytes.len())
    // The slice metadata is the byte length required by Text's representation.
    let text = unsafe { core.mem.transmute<ptr<mut Text>>(slice) }
    Box(text, a)
}

pub fn copy_text_in<A: Allocator>(
    value: read Text,
    allocator: take A
): Box<Text, A> {
    let outcome = capture try_copy_text_in(value, allocator)
    match take outcome {
        success(owner) => owner,
        failure(_) => handle_alloc_error(layout_of_val(value))
    }
}

pub fn try_copy_text(value: read Text): Box<Text> throws AllocError {
    try try_copy_text_in(value, Global())
}
pub fn copy_text(value: read Text): Box<Text> {
    copy_text_in(value, Global())
}

// Moves a String's validated bytes and allocator into an unsized Text owner.
pub fn from_string<A: Allocator>(
    value: take super.string.String<A>
): Box<Text, A> {
    let bytes = value.into_bytes().into_boxed_slice()
    let raw = bytes.into_raw()
    // String guarantees UTF-8 validity; the slice length and initialized byte
    // extent are preserved by the pointer cast.
    let text = unsafe { core.mem.transmute<ptr<mut Text>>(raw.0) }
    unsafe { from_raw_in(text, raw.1) }
}

fn text_from_chars<I: OwnedIterable<Item = char>>(items: take I): Box<Text> {
    var output = super.string.new()
    var source = items.into_iter()
    while true {
        match take source.next() {
            present(value) => { output.push(value) },
            none => { break }
        }
    }
    from_string(output)
}

fn text_from_borrowed_chars<region r, I: OwnedIterable<Item = read char from r>>(
    items: take I
): Box<Text> {
    var output = super.string.new()
    var source = items.into_iter()
    while true {
        match take source.next() {
            present(value) => { output.push(*value) },
            none => { break }
        }
    }
    from_string(output)
}

fn text_from_parts<region r, I: OwnedIterable<Item = read Text from r>>(
    items: take I
): Box<Text> {
    var output = super.string.new()
    var source = items.into_iter()
    while true {
        match take source.next() {
            present(part) => { output.push_str(part) },
            none => { break }
        }
    }
    from_string(output)
}

fn text_from_strings<I: OwnedIterable<Item = super.string.String>>(
    items: take I
): Box<Text> {
    var output = super.string.new()
    var source = items.into_iter()
    while true {
        match take source.next() {
            present(part) => { output.push_str(part.as_text()) },
            none => { break }
        }
    }
    from_string(output)
}

fn text_from_boxes<A: Allocator, I: OwnedIterable<Item = Box<Text, A>>>(
    items: take I
): Box<Text> {
    var output = super.string.new()
    var source = items.into_iter()
    while true {
        match take source.next() {
            present(part) => { output.push_str(part.get()) },
            none => { break }
        }
    }
    from_string(output)
}

pub fn try_new_uninit_in<T, A: Allocator>(
    allocator: take A
): Box<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.uninit(), allocator)
}
pub fn new_uninit_in<T, A: Allocator>(allocator: take A): Box<core.mem.MaybeUninit<T>, A> {
    let result = capture try_new_uninit_in<T, A>(allocator)
    match take result {
        success(owner) => owner,
        failure(_) => handle_alloc_error(layout_of<T>())
    }
}
pub fn try_new_uninit<T>(): Box<core.mem.MaybeUninit<T>> throws AllocError {
    try try_new_uninit_in<T, Global>(Global())
}
pub fn new_uninit<T>(): Box<core.mem.MaybeUninit<T>> { new_uninit_in<T, Global>(Global()) }

pub fn try_new_zeroed_in<T, A: Allocator>(
    allocator: take A
): Box<core.mem.MaybeUninit<T>, A> throws AllocError {
    try try_new_in(core.mem.MaybeUninit<T>.zeroed(), allocator)
}
pub fn new_zeroed_in<T, A: Allocator>(allocator: take A): Box<core.mem.MaybeUninit<T>, A> {
    let result = capture try_new_zeroed_in<T, A>(allocator)
    match take result {
        success(owner) => owner,
        failure(_) => handle_alloc_error(layout_of<T>())
    }
}
pub fn try_new_zeroed<T>(): Box<core.mem.MaybeUninit<T>> throws AllocError {
    try try_new_zeroed_in<T, Global>(Global())
}
pub fn new_zeroed<T>(): Box<core.mem.MaybeUninit<T>> { new_zeroed_in<T, Global>(Global()) }

extend<T: unsized, A: Allocator> Box<T, A> {
    pub fn get(): read T from self { unsafe { read *self.p } }
    pub mut fn get_mut(): mut T from self { unsafe { mut *self.p } }
    pub fn allocator(): read A from self { read self.a }
    pub fn as_ptr(): ptr<mut T> { self.p }
    // The pointer is usable only under the caller's ordinary raw-pointer
    // obligations.
    pub mut fn as_mut_ptr(): ptr<mut T> { self.p }
    // Ownership conversion: the caller becomes responsible for the block and
    // must rebuild it with `from_raw_in` using a compatible allocator.
    pub take fn into_raw(): (ptr<mut T>, A) {
        unsafe {
            let p = self.p
            let a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            (p, a)
        }
    }
    // The allocator is intentionally retained with the leaked allocation.
    pub take fn leak(): ptr<mut T> {
        let p = self.p
        core.mem.forget(take self)
        p
    }
}

extend<T, A: Allocator> Box<core.mem.MaybeUninit<T>, A> {
    pub take fn write(value: take T): Box<T, A> {
        // The uninitialized box owns the exact T layout; initialize it once
        // before transferring the same allocation and allocator as Box<T>.
        unsafe { core.ptr.write(self.p.cast<T>(), value) }
        let raw = self.into_raw()
        unsafe { from_raw_in(raw.0.cast<T>(), raw.1) }
    }

    // Safety: the caller initialized the payload before taking ownership as T.
    pub take unsafe fn assume_init(): Box<T, A> {
        let raw = self.into_raw()
        unsafe { from_raw_in(raw.0.cast<T>(), raw.1) }
    }
}

extend<T, A: Allocator> Box<[core.mem.MaybeUninit<T>], A> {
    // Safety: every element is initialized as T; element layout and length
    // metadata are unchanged by replacing MaybeUninit<T> with T.
    pub take unsafe fn assume_init(): Box<[T], A> {
        let raw = self.into_raw()
        let slice = unsafe { core.mem.transmute<ptr<mut [T]>>(raw.0) }
        unsafe { from_raw_in(slice, raw.1) }
    }
}

extend<T, A: Allocator> Box<T, A> {
    // Moves the value out and releases the block without dropping the value.
    pub take fn into_inner(): T {
        unsafe {
            let p = self.p
            let v = core.ptr.`read`(p)
            var a = core.ptr.`read`(core.ptr.from_ref(self.a))
            a.deallocate(p.cast<u8>(), layout_of<T>())
            core.mem.forget(take self)
            v
        }
    }
}

// Safety: `p` came from `into_raw` (or an equivalent allocation of the
// dynamic layout of `T` by `a`) and holds an initialized `T`.
pub unsafe fn from_raw_in<T: unsized, A: Allocator>(p: ptr<mut T>, a: take A): Box<T, A> { Box(p, a) }
pub unsafe fn from_raw<T: unsized>(p: ptr<mut T>): Box<T> { Box(p, Global()) }


// A box is transparent: comparison, hashing and formatting delegate to the payload.
extend<T: unsized, A: Allocator> Box<T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> Box<T, A> implements AsRef<T> {
    fn as_ref(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> Box<T, A> implements Borrow<T> {
    fn borrow(): read T from self { self.get() }
}
extend<T: unsized, A: Allocator> Box<T, A> implements AsMut<T> {
    mut fn as_mut(): mut T from self { self.get_mut() }
}
extend<T: unsized, A: Allocator> Box<T, A> implements BorrowMut<T> {
    mut fn borrow_mut(): mut T from self { self.get_mut() }
}
extend<T: unsized, A: Allocator> Box<T, A> implements DerefMut {
    type Target = T
    mut fn deref_mut(): mut T from self { self.get_mut() }
}
extend<T: Hasher + unsized, A: Allocator> Box<T, A> implements Hasher {
    mut fn write(bytes: read [u8]): Unit {
        T.(Hasher).write(self.get_mut(), bytes)
    }
    fn finish(): u64 { T.(Hasher).finish(self.get()) }
}
extend<E: Error> Box<E> implements Error {
    fn source<region r>(
        receiver self: read Self from r
    ): (read any Error from r)? {
        E.(Error).source(self.get())
    }
}
extend<I: Iterator + unsized, A: Allocator> Box<I, A> implements Iterator {
    type Item = I.(Iterator).Item
    fn size_hint(): (usize, usize?) {
        I.(Iterator).size_hint(self.get())
    }
    mut fn next(): I.(Iterator).Item? {
        I.(Iterator).next(self.get_mut())
    }
}
extend<I: BidirectionalIterator + unsized, A: Allocator> Box<I, A> implements BidirectionalIterator {
    mut fn next_back(): I.(Iterator).Item? {
        I.(BidirectionalIterator).next_back(self.get_mut())
    }
}
extend<I: ExactSizeIterator + unsized, A: Allocator> Box<I, A> implements ExactSizeIterator {
    fn len(): usize { I.(ExactSizeIterator).len(self.get()) }
}
extend<I: FusedIterator + unsized, A: Allocator> Box<I, A> implements FusedIterator {}

extend<T, A: Allocator> BoxSliceIntoIter<T, A> implements Iterator {
    type Item = T
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
    mut fn next(): T? {
        if self.front == self.back { return none }
        let index = self.front
        self.front += 1usize
        present(unsafe { core.ptr.`read`(self.p.add(index)) })
    }
}
extend<T, A: Allocator> BoxSliceIntoIter<T, A> implements BidirectionalIterator {
    mut fn next_back(): T? {
        if self.front == self.back { return none }
        self.back -= 1usize
        present(unsafe { core.ptr.`read`(self.p.add(self.back)) })
    }
}
extend<T, A: Allocator> BoxSliceIntoIter<T, A> implements ExactSizeIterator {}
extend<T, A: Allocator> BoxSliceIntoIter<T, A> implements FusedIterator {}

extend<T, A: Allocator> Box<[T], A> implements OwnedIterable {
    type Item = T
    type IntoIter = BoxSliceIntoIter<T, A>
    fn into_iter(receiver self: take Self): BoxSliceIntoIter<T, A> {
        let len = self.get().len()
        let layout = layout_of_val(self.get())
        let raw = self.into_raw()
        BoxSliceIntoIter(raw.0.cast<T>(), 0usize, len, layout, raw.1)
    }
}
extend<T, A: Allocator> Box<[T], A> implements Iterable {
    type Item = T
    type Iter<region r> = SliceIter<region r, T>
    fn iter<region r>(
        receiver self: read Self from r
    ): SliceIter<region r, T> {
        self.get().iter()
    }
}
extend<T, A: Allocator> Box<[T], A> implements MutableIterable {
    type Item = T
    type IterMut<region r> = SliceIterMut<region r, T>
    fn iter_mut<region r>(
        receiver self: mut Self from r
    ): SliceIterMut<region r, T> {
        self.get_mut().iter_mut()
    }
}
extend<T, const N: usize, A: Allocator> Box<[T; N], A> implements OwnedIterable {
    type Item = T
    type IntoIter = BoxSliceIntoIter<T, A>
    fn into_iter(receiver self: take Self): BoxSliceIntoIter<T, A> {
        let layout = layout_of_val(self.get())
        let raw = self.into_raw()
        // The array allocation contains exactly N contiguous initialized T
        // values; the iterator retains its exact layout and allocator.
        BoxSliceIntoIter(raw.0.cast<T>(), 0usize, N, layout, raw.1)
    }
}
extend<T, const N: usize, A: Allocator> Box<[T; N], A> implements Iterable {
    type Item = T
    type Iter<region r> = SliceIter<region r, T>
    fn iter<region r>(
        receiver self: read Self from r
    ): SliceIter<region r, T> {
        // SAFETY: self owns an initialized array of exactly N contiguous T
        // values, and the returned view is bounded by the receiver region.
        let slice = unsafe { read *slice_ptr(self.p.cast<T>(), N) }
        slice.iter()
    }
}
extend<T, const N: usize, A: Allocator> Box<[T; N], A> implements MutableIterable {
    type Item = T
    type IterMut<region r> = SliceIterMut<region r, T>
    fn iter_mut<region r>(
        receiver self: mut Self from r
    ): SliceIterMut<region r, T> {
        // SAFETY: the exclusive receiver owns an initialized array of exactly
        // N contiguous T values for the returned mutable-view region.
        let slice = unsafe { mut *slice_ptr_mut(self.p.cast<T>(), N) }
        slice.iter_mut()
    }
}
extend<T> Box<[T]> implements FromItems<T> {
    static fn from_iter<I: OwnedIterable<Item = T>>(items: take I): Box<[T]> {
        let values = super.vec.List<T>.(FromItems<T>).from_iter(items)
        values.into_boxed_slice()
    }
}
extend Box<Text> implements FromItems<char> {
    static fn from_iter<I: OwnedIterable<Item = char>>(items: take I): Box<Text> {
        text_from_chars(items)
    }
}
extend<region r> Box<Text> implements FromItems<read char from r> {
    static fn from_iter<I: OwnedIterable<Item = read char from r>>(
        items: take I
    ): Box<Text> {
        text_from_borrowed_chars(items)
    }
}
extend<region r> Box<Text> implements FromItems<read Text from r> {
    static fn from_iter<I: OwnedIterable<Item = read Text from r>>(
        items: take I
    ): Box<Text> {
        text_from_parts(items)
    }
}
extend Box<Text> implements FromItems<super.string.String> {
    static fn from_iter<I: OwnedIterable<Item = super.string.String>>(
        items: take I
    ): Box<Text> {
        text_from_strings(items)
    }
}
extend<A: Allocator> Box<Text> implements FromItems<Box<Text, A>> {
    static fn from_iter<I: OwnedIterable<Item = Box<Text, A>>>(
        items: take I
    ): Box<Text> {
        text_from_boxes<A>(items)
    }
}
extend<T: Clone, A: Allocator + Clone> Box<T, A> implements Clone {
    fn clone(): Box<T, A> { new_in(self.get().clone(), self.a.clone()) }
}
extend<T> Box<T> implements From<T> {
    static fn from(value: take T): Box<T> { new(value) }
}
extend<T: Default> Box<T> implements Default {
    static fn default(): Box<T> { new(T.(Default).default()) }
}
extend<T> Box<[T]> implements Default {
    static fn default(): Box<[T]> {
        unsafe { new_zeroed_slice<T>(0usize).assume_init() }
    }
}
extend Box<Text> implements Default {
    static fn default(): Box<Text> { copy_text("") }
}
extend<T: PartialEq, A: Allocator> Box<T, A> implements PartialEq {
    fn eq(other: read Box<T, A>): bool { self.get().eq(other.get()) }
}
extend<T: Eq, A: Allocator> Box<T, A> implements Eq {}
extend<T: PartialOrd, A: Allocator> Box<T, A> implements PartialOrd {
    fn partial_cmp(other: read Box<T, A>): Ordering? { self.get().partial_cmp(other.get()) }
}
extend<T: Ord, A: Allocator> Box<T, A> implements Ord {
    fn cmp(other: read Box<T, A>): Ordering { self.get().cmp(other.get()) }
}
extend<T: Hash, A: Allocator> Box<T, A> implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.get().hash(mut state) }
}
extend<T: fmt.Display, A: Allocator> Box<T, A> implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Display).fmt(self.get(), mut f) }
}
extend<T: fmt.Debug, A: Allocator> Box<T, A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Debug).fmt(self.get(), mut f) }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<T: Transferable, A: Allocator + Transferable> Box<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> Box<T, A> implements Shareable {}

// Unique heap owner whose payload stays at its address until destruction.
// Moving the handle never moves the payload; safe code reaches the payload
// mutably only through a pinned view, or directly when it is Unpin.
pub type Pinned<T: unsized, A: Allocator = super.alloc.Global> {
    p: ptr<mut T>
    a: A
    drop {
        let _free = unsafe { free_block(self.p.cast<u8>(), layout_of_val(self.get_ref()), core.ptr.from_mut(self.a)) }
        unsafe { core.ptr.drop_in_place(self.p) }
    }
}

// `pinned heap value`: the payload is pinned from its first use.
pub fn pin<T>(value: take T): Pinned<T> { new(value).into_pinned() }

extend<T: unsized, A: Allocator> Box<T, A> {
    // A unique heap payload does not move when its owner moves, so pinning
    // consumes the owner and nothing safe can move the payload out again.
    pub take fn into_pinned(): Pinned<T, A> {
        let raw = self.into_raw()
        Pinned(raw.0, raw.1)
    }
}

extend<T: unsized, A: Allocator> Pinned<T, A> {
    pub fn as_ref(): pinned read T from self { unsafe { core.pin.Pin.new_unchecked(read *self.p) } }
    pub mut fn as_mut(): pinned mut T from self { unsafe { core.pin.Pin.new_unchecked(mut *self.p) } }
    pub fn get_ref(): read T from self { unsafe { read *self.p } }
    pub fn allocator(): read A from self { read self.a }
    // Safety: the payload stays at its address until it is destroyed, even
    // after the returned owner no longer pins it.
    pub take unsafe fn into_inner_unchecked(): Box<T, A> {
        unsafe {
            let p = self.p
            let a = core.ptr.`read`(core.ptr.from_ref(self.a))
            core.mem.forget(take self)
            from_raw_in(p, a)
        }
    }
}

extend<T: unsized + Unpin, A: Allocator> Pinned<T, A> {
    pub mut fn get_mut(): mut T from self { unsafe { mut *self.p } }
    pub take fn into_inner(): Box<T, A> { unsafe { self.into_inner_unchecked() } }
}

extend<T: unsized, A: Allocator> Pinned<T, A> implements Deref {
    type Target = T
    fn deref(): read T from self { self.get_ref() }
}
extend<T: unsized + Unpin, A: Allocator> Pinned<T, A> implements DerefMut {
    type Target = T
    mut fn deref_mut(): mut T from self { self.get_mut() }
}
// Awaiting a pinned owner polls its payload in place.
extend<T: unsized + Future, A: Allocator> Pinned<T, A> implements Future {
    type Output = T.(Future).Output
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<T.(Future).Output> {
        let owner: mut Pinned<T, A> = unsafe { self.get_unchecked_mut() }
        // Project the pinned owner, not the blanket AsMut on its view handle.
        T.(Future).poll((*owner).as_mut(), mut cx)
    }
}
extend<T: fmt.Debug, A: Allocator> Pinned<T, A> implements fmt.Debug {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error { try T.(fmt.Debug).fmt(self.get_ref(), mut f) }
}
// The handle is movable; pinning is a property of the payload's storage.
unsafe extend<T: unsized, A: Allocator> Pinned<T, A> implements Unpin {}
unsafe extend<T: Transferable, A: Allocator + Transferable> Pinned<T, A> implements Transferable {}
unsafe extend<T: Shareable, A: Allocator + Shareable> Pinned<T, A> implements Shareable {}
extend<T: Default> Pinned<T> implements Default {
    static fn default(): Pinned<T> { pin(T.(Default).default()) }
}
extend<T> Pinned<[T]> implements Default {
    static fn default(): Pinned<[T]> {
        let owner = unsafe { new_zeroed_slice<T>(0usize).assume_init() }
        let raw = owner.into_raw()
        Pinned(raw.0, raw.1)
    }
}
extend Pinned<Text> implements Default {
    static fn default(): Pinned<Text> { copy_text("").into_pinned() }
}
