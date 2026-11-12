import super.cmp.{PartialEq, PartialOrd, Ord, Ordering}
import super.iter.{Iterator, BidirectionalIterator, Iterable, MutableIterable}
import super.clone.Clone
import super.borrow.{AsRef, AsMut, Borrow, BorrowMut}
import super.ops.{Index, IndexMut}
import super.fmt

copy type Raw { data: ptr<read u8>; len: usize }

type DropValuesGuard<T> {
    p: ptr<mut T>
    n: usize
    drop { self.run() }
}
extend<T> DropValuesGuard<T> {
    mut fn run(): Unit {
        while self.n != 0usize {
            // Advance before dropping so unwinding never revisits this value.
            let current = self.p
            self.p = unsafe { self.p.add(1usize) }
            self.n -= 1usize
            unsafe { core.ptr.drop_in_place(current) }
        }
    }
}

// Safety: `p` points to `n` initialized, aligned `T` values that may be
// exclusively destroyed. The range remains valid until all drops complete.
pub unsafe fn drop_values<T>(p: ptr<mut T>, n: usize): Unit {
    var guard = DropValuesGuard(p, n)
    guard.run()
}

pub const fn data(read bytes: [u8]): ptr<read u8> {
    let fat = core.ptr.from_ref(bytes)
    let raw = unsafe { core.mem.transmute<Raw>(fat) }
    raw.data
}

// Safety: start <= end <= bytes.len().
pub unsafe const fn subslice_unchecked(read bytes: [u8], start: usize, end: usize): read [u8] from bytes {
    let raw = Raw(data(bytes).add(start), end - start)
    let fat = unsafe { core.mem.transmute<ptr<read [u8]>>(raw) }
    unsafe { read *fat }
}

pub const fn subslice(read bytes: [u8], start: usize, end: usize): (read [u8] from bytes)? {
    if start <= end && end <= bytes.len() {
        present(unsafe { subslice_unchecked(bytes, start, end) })
    } else {
        none
    }
}

copy type RawParts<T> { data: ptr<read T>; len: usize }
copy type RawPartsMut<T> { data: ptr<mut T>; len: usize }

fn gcd(left: usize, right: usize): usize {
    var a = left
    var b = right
    while b != 0usize {
        let remainder = a % b
        a = b
        b = remainder
    }
    a
}

// Empty slice pointers remain non-null and aligned, but are never dereferenced.
fn aligned_dangling<T>(): ptr<mut T> {
    core.ptr.NonNull<T>.dangling().as_ptr()
}

// Ensures the suffix still begins at a `T` boundary for non-dividing sizes.
fn alignment_partition<T, U>(
    data: ptr<read T>,
    len: usize
): (usize, usize, usize) {
    let size_t = core.mem.size_of<T>()
    let size_u = core.mem.size_of<U>()
    if size_t == 0usize || size_u == 0usize { return (len, 0usize, 0usize) }

    let pointer = core.ptr.NonNull<T>.new(data.cast_mut()).unwrap()
    let prefix = pointer.align_offset(core.mem.align_of<U>())
    if prefix == 0xffffffffffffffffusize || prefix > len {
        return (len, 0usize, 0usize)
    }
    let remaining = len - prefix
    let bytes = match remaining.checked_mul(size_t) {
        present(value) => value,
        none => super.panic.panic("slice byte size overflow")
    }
    let step = size_t / gcd(size_t, size_u)
    let max_middle = bytes / size_u
    let middle = max_middle - max_middle % step
    let middle_bytes = middle * size_u
    let suffix = remaining - middle_bytes / size_t
    (prefix, middle, suffix)
}

// Safety: `data` is valid for reads of `len` initialized elements for all of
// region `r`, is aligned, and no exclusive access overlaps it during `r`.
pub unsafe const fn from_raw_parts<region r, T>(data: ptr<read T>, len: usize): read [T] from r {
    let raw = RawParts(data, len)
    let fat = unsafe { core.mem.transmute<ptr<read [T]>>(raw) }
    unsafe { read *fat }
}

// Safety: as `from_raw_parts`, for reads and writes, with no other access to
// the elements during `r`.
pub unsafe fn from_raw_parts_mut<region r, T>(data: ptr<mut T>, len: usize): mut [T] from r {
    let raw = RawPartsMut(data, len)
    let fat = unsafe { core.mem.transmute<ptr<mut [T]>>(raw) }
    unsafe { mut *fat }
}

// Replacing the holder preserves r while partitioning its original initialized extent.
pub fn split_off_first<region r, T>(mut view: read [T] from r): (read T from r)? {
    let n = view.len()
    if n == 0usize { return none }
    let data = view.as_ptr()
    unsafe {
        view = from_raw_parts(data.add(1usize), n - 1usize)
        present(read *data)
    }
}

pub fn split_off_last<region r, T>(mut view: read [T] from r): (read T from r)? {
    let n = view.len()
    if n == 0usize { return none }
    let data = view.as_ptr()
    unsafe {
        view = from_raw_parts(data, n - 1usize)
        present(read *data.add(n - 1usize))
    }
}

// Safety: original is nonempty; both outputs partition its exclusive region.
unsafe fn split_owned_endpoint<region r, T>(
    take original: mut [T] from r, front: bool
): (mut T from r, mut [T] from r) {
    let n = original.len()
    let data = original.as_mut_ptr()
    let index = if front { 0usize } else { n - 1usize }
    let start = if front { 1usize } else { 0usize }
    unsafe {
        (mut *data.add(index), from_raw_parts_mut(data.add(start), n - 1usize))
    }
}

// Safety: at <= original.len(); both outputs partition its exclusive region.
unsafe fn split_owned_at<region r, T>(
    take original: mut [T] from r, at: usize
): (mut [T] from r, mut [T] from r) {
    let n = original.len()
    let data = original.as_mut_ptr()
    unsafe { (from_raw_parts_mut(data, at), from_raw_parts_mut(data.add(at), n - at)) }
}

pub fn split_off_first_mut<region r, T>(mut view: mut [T] from r): (mut T from r)? {
    let n = view.len()
    let data = view.as_mut_ptr()
    unsafe {
        let original = core.mem.replace(mut view, from_raw_parts_mut(data, 0usize))
        if n == 0usize {
            view = take original
            return none
        }
        let parts = split_owned_endpoint(take original, true)
        view = take parts.1
        present(take parts.0)
    }
}

pub fn split_off_last_mut<region r, T>(mut view: mut [T] from r): (mut T from r)? {
    let n = view.len()
    let data = view.as_mut_ptr()
    unsafe {
        let original = core.mem.replace(mut view, from_raw_parts_mut(data, 0usize))
        if n == 0usize {
            view = take original
            return none
        }
        let parts = split_owned_endpoint(take original, false)
        view = take parts.1
        present(take parts.0)
    }
}

interface SplitOffRange: super.iter.RangeBounds<usize> {}
extend super.iter.RangeFrom<usize> implements SplitOffRange {}
extend super.iter.RangeTo<usize> implements SplitOffRange {}
extend super.iter.RangeToInclusive<usize> implements SplitOffRange {}

fn split_off_point<R: SplitOffRange>(read range: R, len: usize): (usize, bool)? {
    match take (range.start_bound(), range.end_bound()) {
        (super.iter.Bound.Included(start), super.iter.Bound.Unbounded) => {
            if *start <= len { present((*start, false)) } else { none }
        },
        (super.iter.Bound.Unbounded, super.iter.Bound.Excluded(end)) => {
            if *end <= len { present((*end, true)) } else { none }
        },
        (super.iter.Bound.Unbounded, super.iter.Bound.Included(end)) => {
            if *end < len { present((*end + 1usize, true)) } else { none }
        },
        _ => none
    }
}

pub fn split_off_mut<region r, T, R: SplitOffRange>(
    mut view: mut [T] from r, take range: R
): (mut [T] from r)? {
    let n = view.len()
    let split = split_off_point(range, n)
    let data = view.as_mut_ptr()
    unsafe {
        let original = core.mem.replace(mut view, from_raw_parts_mut(data, 0usize))
        let point = match take split {
            present(value) => value,
            none => {
                view = take original
                return none
            }
        }
        let parts = split_owned_at(take original, point.0)
        if point.1 {
            view = take parts.1
            return present(take parts.0)
        }
        view = take parts.0
        present(take parts.1)
    }
}

copy type RawMut<T> { data: ptr<mut T>; len: usize }

// The fat slice pointer is represented by its data pointer and length here.
const fn mutable_data_pointer<T>(mut xs: [T]): ptr<mut T> {
    let fat = core.ptr.from_mut(xs)
    let raw = unsafe { core.mem.transmute<RawMut<T>>(fat) }
    raw.data
}

// Safety: `index < xs.len()`.
unsafe fn element<T>(mut xs: [T], index: usize): ptr<mut T> {
    mutable_data_pointer(xs).add(index)
}

extend<T> [T] {
    pub fn is_empty(): bool { self.len() == 0usize }
    pub fn get(index: usize): (read T from self)? {
        if index < self.len() { present(read self[index]) } else { none }
    }
    // Safety: `index` is less than the slice length.
    pub unsafe fn get_unchecked(index: usize): read T from self {
        let raw = unsafe { core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self)) }
        unsafe { read *raw.data.add(index) }
    }
    pub mut fn get_mut(index: usize): (mut T from self)? {
        if index < self.len() { present(mut self[index]) } else { none }
    }
    // Safety: `index` is less than the slice length.
    pub mut unsafe fn get_unchecked_mut(index: usize): mut T from self {
        unsafe { mut *mutable_data_pointer(mut self).add(index) }
    }
    pub fn first(): (read T from self)? { self.get(0usize) }
    pub fn last(): (read T from self)? {
        if self.len() == 0usize { none } else { self.get(self.len() - 1usize) }
    }
    pub mut fn first_mut(): (mut T from self)? { self.get_mut(0usize) }
    pub mut fn last_mut(): (mut T from self)? {
        if self.len() == 0usize { none } else { self.get_mut(self.len() - 1usize) }
    }
    pub const fn as_ptr(): ptr<read T> {
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        raw.data
    }
    pub mut fn as_mut_ptr(): ptr<mut T> {
        mutable_data_pointer(mut self)
    }
    pub fn as_ptr_range(): super.iter.Range<ptr<read T>> {
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the slice pointer is valid through its one-past-end position.
        let end = unsafe { raw.data.add(self.len()) }
        super.iter.Range(raw.data, end)
    }
    pub mut const fn as_mut_ptr_range(): super.iter.Range<ptr<mut T>> {
        let n = self.len()
        let data = mutable_data_pointer(mut self)
        // Safety: the exclusive slice pointer is valid through one-past-end.
        let end = unsafe { data.add(n) }
        super.iter.Range(data, end)
    }
    pub fn element_offset(read element: T): usize? {
        let size = core.mem.size_of<T>()
        if size == 0usize { super.panic.panic("element_offset requires non-zero-sized elements") }
        let start = self.as_ptr().addr()
        let address = core.ptr.from_ref(element).addr()
        if address < start { return none }
        let bytes = address - start
        if bytes % size != 0usize { return none }
        let index = bytes / size
        if index < self.len() { present(index) } else { none }
    }
    pub fn subslice_range(read part: [T]): (super.iter.Range<usize>)? {
        let size = core.mem.size_of<T>()
        if size == 0usize { super.panic.panic("subslice_range requires non-zero-sized elements") }
        let start = self.as_ptr().addr()
        let address = part.as_ptr().addr()
        if address < start { return none }
        let bytes = address - start
        if bytes % size != 0usize { return none }
        let index = bytes / size
        if index > self.len() || part.len() > self.len() - index { return none }
        present(super.iter.Range(index, index + part.len()))
    }
    // Safety: middle bytes are initialized valid `U`; source bounds and
    // provenance are retained, and the partition keeps each view in-bounds.
    pub unsafe fn align_to<U>(): (
        read [T] from self,
        read [U] from self,
        read [T] from self
    ) {
        let len = self.len()
        let data = self.as_ptr()
        let (prefix, middle_len, suffix_len) =
            alignment_partition<T, U>(data, len)
        let suffix_start = len - suffix_len
        let middle_data = if middle_len == 0usize {
            aligned_dangling<U>().cast_const()
        } else {
            unsafe { data.add(prefix).cast<U>() }
        }
        let first = unsafe { sub<T>(read self, 0usize, prefix) }
        let middle = unsafe { from_raw_parts(middle_data, middle_len) }
        let last = unsafe { sub<T>(read self, suffix_start, len) }
        (first, middle, last)
    }
    // Safety: middle bytes are initialized valid `U`; the exclusive source
    // borrow yields disjoint, aligned views bounded by its allocation.
    pub mut unsafe fn align_to_mut<U>(): (
        mut [T] from self,
        mut [U] from self,
        mut [T] from self
    ) {
        let len = self.len()
        let data = mutable_data_pointer(mut self)
        let (prefix, middle_len, suffix_len) =
            alignment_partition<T, U>(data.cast_const(), len)
        let suffix_start = len - suffix_len
        let middle_data = if middle_len == 0usize {
            aligned_dangling<U>()
        } else {
            unsafe { data.add(prefix).cast<U>() }
        }
        let first = unsafe { from_raw_parts_mut(data, prefix) }
        let middle = unsafe { from_raw_parts_mut(middle_data, middle_len) }
        let last = unsafe { from_raw_parts_mut(data.add(suffix_start), suffix_len) }
        (first, middle, last)
    }
    pub mut fn swap(a: usize, b: usize) {
        if a >= self.len() || b >= self.len() { super.panic.panic("swap index out of bounds") }
        if a != b {
            unsafe { core.ptr.swap(element<T>(mut self, a), element<T>(mut self, b)) }
        }
    }
    pub mut fn reverse() {
        var i = 0usize
        var j = self.len()
        while i + 1usize < j {
            j -= 1usize
            self.swap(i, j)
            i += 1usize
        }
    }
}

extend<T> [T] {
    pub const fn first_chunk<const N: usize>(): (read [T; N] from self)? {
        if N > self.len() { return none }
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the checked length covers all N initialized elements.
        present(unsafe { read *raw.data.cast<[T; N]>() })
    }

    pub const fn last_chunk<const N: usize>(): (read [T; N] from self)? {
        if N > self.len() { return none }
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the checked suffix contains N initialized elements.
        present(unsafe { read *raw.data.add(self.len() - N).cast<[T; N]>() })
    }

    pub const fn split_first_chunk<const N: usize>(): ((read [T; N] from self), (read [T] from self))? {
        if N > self.len() { return none }
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the array and suffix are in-bounds parts of the source slice.
        let first = unsafe { read *raw.data.cast<[T; N]>() }
        let rest = unsafe { sub<T>(read self, N, self.len()) }
        present((first, rest))
    }

    pub const fn split_last_chunk<const N: usize>(): ((read [T] from self), (read [T; N] from self))? {
        if N > self.len() { return none }
        let start = self.len() - N
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the prefix and array are in-bounds parts of the source slice.
        let last = unsafe { read *raw.data.add(start).cast<[T; N]>() }
        let rest = unsafe { sub<T>(read self, 0usize, start) }
        present((rest, last))
    }

    pub const fn as_array<const N: usize>(): (read [T; N] from self)? {
        if self.len() != N { return none }
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the checked length is exactly one initialized array.
        present(unsafe { read *raw.data.cast<[T; N]>() })
    }

    pub mut const fn as_mut_array<const N: usize>(): (mut [T; N] from self)? {
        if self.len() != N { return none }
        let data = mutable_data_pointer(mut self)
        present(unsafe { mut *data.cast<[T; N]>() })
    }

    pub const fn as_chunks<const N: usize>(): (read [[T; N]] from self, read [T] from self) {
        if N == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let count = n / N
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: count arrays cover a checked prefix; the tail is disjoint.
        let arrays = unsafe {
            core.mem.transmute<ptr<read [[T; N]]>>(
                RawParts(raw.data.cast<[T; N]>(), count)
            )
        }
        let remainder = unsafe { sub<T>(read self, count * N, n) }
        (unsafe { read *arrays }, remainder)
    }

    pub mut const fn as_chunks_mut<const N: usize>(): (mut [[T; N]] from self, mut [T] from self) {
        if N == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let count = n / N
        let prefix_len = count * N
        let data = mutable_data_pointer(mut self)
        // Safety: the array prefix and remainder are disjoint in-bounds parts.
        let arrays = unsafe {
            core.mem.transmute<ptr<mut [[T; N]]>>(
                RawPartsMut(data.cast<[T; N]>(), count)
            )
        }
        let remainder = unsafe {
            core.mem.transmute<ptr<mut [T]>>(
                RawPartsMut(data.add(prefix_len), n - prefix_len)
            )
        }
        (unsafe { mut *arrays }, unsafe { mut *remainder })
    }

    pub const fn as_rchunks<const N: usize>(): (read [T] from self, read [[T; N]] from self) {
        if N == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let remainder_len = n % N
        let count = n / N
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        // Safety: the remainder and aligned array suffix partition the slice.
        let remainder = unsafe { sub<T>(read self, 0usize, remainder_len) }
        let arrays = unsafe {
            core.mem.transmute<ptr<read [[T; N]]>>(
                RawParts(raw.data.add(remainder_len).cast<[T; N]>(), count)
            )
        }
        (remainder, unsafe { read *arrays })
    }

    pub mut const fn as_rchunks_mut<const N: usize>(): (mut [T] from self, mut [[T; N]] from self) {
        if N == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let remainder_len = n % N
        let count = n / N
        let data = mutable_data_pointer(mut self)
        // Safety: these two exclusive ranges partition the original slice.
        let remainder = unsafe {
            core.mem.transmute<ptr<mut [T]>>(
                RawPartsMut(data, remainder_len)
            )
        }
        let arrays = unsafe {
            core.mem.transmute<ptr<mut [[T; N]]>>(
                RawPartsMut(data.add(remainder_len).cast<[T; N]>(), count)
            )
        }
        (unsafe { mut *remainder }, unsafe { mut *arrays })
    }

    // Safety: N is nonzero and the slice length is divisible by N.
    pub unsafe const fn as_chunks_unchecked<const N: usize>(): read [[T; N]] from self {
        if N == 0usize { super.panic.panic("chunk size must be nonzero") }
        if self.len() % N != 0usize { super.panic.panic("slice length must be divisible by chunk size") }
        let raw = unsafe {
            core.mem.transmute<RawParts<T>>(core.ptr.from_ref(self))
        }
        let arrays = unsafe {
            core.mem.transmute<ptr<read [[T; N]]>>(
                RawParts(raw.data.cast<[T; N]>(), self.len() / N)
            )
        }
        unsafe { read *arrays }
    }

    // Safety: N is nonzero and the slice length is divisible by N.
    pub mut unsafe const fn as_chunks_unchecked_mut<const N: usize>(): mut [[T; N]] from self {
        if N == 0usize { super.panic.panic("chunk size must be nonzero") }
        if self.len() % N != 0usize { super.panic.panic("slice length must be divisible by chunk size") }
        let count = self.len() / N
        let data = mutable_data_pointer(mut self)
        // Safety: the caller guarantees all elements belong to full arrays.
        let arrays = unsafe {
            core.mem.transmute<ptr<mut [[T; N]]>>(
                RawPartsMut(data.cast<[T; N]>(), count)
            )
        }
        unsafe { mut *arrays }
    }
}

extend<T, const N: usize> [[T; N]] {
    pub fn as_flattened(): read [T] from self {
        let length = match self.len().checked_mul(N) {
            present(n) => n,
            none => super.panic.panic("flattened slice length overflow")
        }
        let raw = unsafe {
            core.mem.transmute<RawParts<[T; N]>>(core.ptr.from_ref(self))
        }
        // Safety: arrays are contiguous and the checked length is their
        // element count, with the original provenance and alignment retained.
        let flat = unsafe {
            core.mem.transmute<ptr<read [T]>>(
                RawParts(raw.data.cast<T>(), length)
            )
        }
        unsafe { read *flat }
    }

    pub mut fn as_flattened_mut(): mut [T] from self {
        let length = match self.len().checked_mul(N) {
            present(n) => n,
            none => super.panic.panic("flattened slice length overflow")
        }
        let data = mutable_data_pointer(mut self).cast<T>()
        // Safety: the exclusive flattened view covers exactly the array data.
        let flat = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawPartsMut(data, length))
        }
        unsafe { mut *flat }
    }
}

extend<T: PartialEq> [T] {
    pub fn contains(read value: T): bool {
        var i = 0usize
        while i < self.len() {
            if self[i] == value { return true }
            i += 1usize
        }
        false
    }
    pub fn starts_with(read prefix: [T]): bool {
        if prefix.len() > self.len() { return false }
        var i = 0usize
        while i < prefix.len() {
            if self[i] != prefix[i] { return false }
            i += 1usize
        }
        true
    }
    pub fn ends_with(read suffix: [T]): bool {
        if suffix.len() > self.len() { return false }
        let offset = self.len() - suffix.len()
        var i = 0usize
        while i < suffix.len() {
            if self[offset + i] != suffix[i] { return false }
            i += 1usize
        }
        true
    }
    pub fn strip_prefix(read prefix: [T]): (read [T] from self)? {
        if !self.starts_with(prefix) { return none }
        present(unsafe { sub<T>(read self, prefix.len(), self.len()) })
    }
    pub fn strip_suffix(read suffix: [T]): (read [T] from self)? {
        if !self.ends_with(suffix) { return none }
        present(unsafe { sub<T>(read self, 0usize, self.len() - suffix.len()) })
    }
    pub fn strip_circumfix(
        read prefix: [T],
        read suffix: [T]
    ): (read [T] from self)? {
        if prefix.len() > self.len() ||
            suffix.len() > self.len() - prefix.len() {
            return none
        }
        if !self.starts_with(prefix) { return none }
        let end = self.len() - suffix.len()
        let tail = unsafe { sub<T>(read self, end, self.len()) }
        if !tail.ends_with(suffix) { return none }
        present(unsafe { sub<T>(read self, prefix.len(), end) })
    }
}

fn ascii_space(byte: u8): bool {
    byte == 9u8 || byte == 10u8 || byte == 12u8 || byte == 13u8 || byte == 32u8
}

fn ascii_lower(byte: u8): u8 {
    if byte >= 65u8 && byte <= 90u8 { byte + 32u8 } else { byte }
}

fn ascii_upper(byte: u8): u8 {
    if byte >= 97u8 && byte <= 122u8 { byte - 32u8 } else { byte }
}

extend [u8] {
    pub fn is_ascii(): bool {
        var index = 0usize
        while index < self.len() {
            if self[index] > 127u8 { return false }
            index += 1usize
        }
        true
    }

    pub fn eq_ignore_ascii_case(read other: [u8]): bool {
        if self.len() != other.len() { return false }
        var index = 0usize
        while index < self.len() {
            if ascii_lower(self[index]) != ascii_lower(other[index]) {
                return false
            }
            index += 1usize
        }
        true
    }

    pub fn trim_ascii_start(): read [u8] from self {
        var start = 0usize
        while start < self.len() && ascii_space(self[start]) {
            start += 1usize
        }
        self.subslice(start, self.len()).unwrap()
    }

    pub fn trim_ascii_end(): read [u8] from self {
        var end = self.len()
        while end > 0usize && ascii_space(self[end - 1usize]) {
            end -= 1usize
        }
        self.subslice(0usize, end).unwrap()
    }

    pub fn trim_ascii(): read [u8] from self {
        self.trim_ascii_start().trim_ascii_end()
    }

    pub mut fn make_ascii_lowercase(): Unit {
        var index = 0usize
        while index < self.len() {
            self[index] = ascii_lower(self[index])
            index += 1usize
        }
    }

    pub mut fn make_ascii_uppercase(): Unit {
        var index = 0usize
        while index < self.len() {
            self[index] = ascii_upper(self[index])
            index += 1usize
        }
    }
}

extend<T: Ord> [T] {
    // Err carries the insertion point; the slice must be sorted ascending.
    pub fn binary_search(read value: T): usize throws usize {
        var low = 0usize
        var high = self.len()
        while low < high {
            let mid = low + (high - low) / 2usize
            let order = self[mid].cmp(value)
            if order.is_lt() {
                low = mid + 1usize
            } else {
                if order.is_gt() { high = mid } else { return mid }
            }
        }
        throw low
    }
    pub fn is_sorted(): bool {
        var i = 1usize
        while i < self.len() {
            if self[i].cmp(read self[i - 1usize]).is_lt() { return false }
            i += 1usize
        }
        true
    }
    // In-place introsort: O(n log n) worst case, no allocation, NOT stable.
    pub mut fn sort_unstable() {
        introsort(mut self, fn(read a: T, read b: T): bool { a.cmp(b).is_lt() })
    }
}

extend<T> [T] {
    pub fn binary_search_by<F: mut fn(read T): Ordering>(take compare: F): usize throws usize {
        var comparator = take compare
        var low = 0usize
        var high = self.len()
        while low < high {
            let mid = low + (high - low) / 2usize
            let order = comparator(read self[mid])
            if order.is_lt() {
                low = mid + 1usize
            } else {
                if order.is_gt() { high = mid } else { return mid }
            }
        }
        throw low
    }
    pub fn binary_search_by_key<K: Ord, F: mut fn(read T): K>(read key: K, take project: F): usize throws usize {
        var key_fn = take project
        var low = 0usize
        var high = self.len()
        while low < high {
            let mid = low + (high - low) / 2usize
            let current = key_fn(read self[mid])
            let order = current.cmp(key)
            if order.is_lt() {
                low = mid + 1usize
            } else {
                if order.is_gt() { high = mid } else { return mid }
            }
        }
        throw low
    }
    pub fn partition_point<F: mut fn(read T): bool>(take before: F): usize {
        var predicate = take before
        var low = 0usize
        var high = self.len()
        while low < high {
            let mid = low + (high - low) / 2usize
            if predicate(read self[mid]) {
                low = mid + 1usize
            } else {
                high = mid
            }
        }
        low
    }
    pub fn is_sorted_by<F: mut fn(read T, read T): bool>(take compare: F): bool {
        var comparator = take compare
        var i = 1usize
        while i < self.len() {
            if !comparator(read self[i - 1usize], read self[i]) { return false }
            i += 1usize
        }
        true
    }
    pub fn is_sorted_by_key<K: PartialOrd, F: mut fn(read T): K>(take key: F): bool {
        var key_fn = take key
        var i = 1usize
        while i < self.len() {
            let previous = key_fn(read self[i - 1usize])
            let current = key_fn(read self[i])
            match previous.partial_cmp(read current) {
                present(order) => { if order.is_gt() { return false } },
                none => { return false }
            }
            i += 1usize
        }
        true
    }
}

extend<T> [T] {
    pub mut fn sort_unstable_by<F: mut fn(read T, read T): Ordering>(take compare: F) {
        var comparator = take compare
        introsort(mut self, fn(read a: T, read b: T): bool {
            comparator(a, b).is_lt()
        })
    }
    pub mut fn sort_unstable_by_key<K: Ord, F: mut fn(read T): K>(take key: F) {
        var key_fn = take key
        introsort(mut self, fn(read a: T, read b: T): bool {
            let left = key_fn(a)
            let right = key_fn(b)
            left.cmp(read right).is_lt()
        })
    }
}

extend<T: Ord> [T] {
    pub mut fn select_nth_unstable(
        nth: usize
    ): (mut [T] from self, mut T from self, mut [T] from self) {
        self.select_nth_unstable_by(nth, fn(read a: T, read b: T): Ordering { a.cmp(b) })
    }
}

extend<T> [T] {
    pub mut fn select_nth_unstable_by<F: mut fn(read T, read T): Ordering>(
        nth: usize,
        take compare: F
    ): (mut [T] from self, mut T from self, mut [T] from self) {
        var comparator = take compare
        var less = fn(read a: T, read b: T): bool {
            comparator(a, b).is_lt()
        }
        let n = self.len()
        if nth >= n { super.panic.panic("selection index out of bounds") }
        var low = 0usize
        var high = n
        var budget = n.saturating_mul(4usize)
        while high - low > 1usize {
            let length = high - low
            if length > budget {
                linear_select(mut self, low, high, nth, mut less)
                break
            }
            budget -= length
            let mid = low + (high - low) / 2usize
            let last = high - 1usize
            if less(read self[mid], read self[low]) { self.swap(mid, low) }
            if less(read self[last], read self[mid]) {
                self.swap(last, mid)
                if less(read self[mid], read self[low]) { self.swap(mid, low) }
            }
            self.swap(mid, last)
            let pivot = last
            var lower = low
            var scan = low
            var greater = pivot
            while scan < greater {
                if less(read self[scan], read self[pivot]) {
                    self.swap(scan, lower)
                    lower += 1usize
                    scan += 1usize
                } else if less(read self[pivot], read self[scan]) {
                    greater -= 1usize
                    self.swap(scan, greater)
                } else {
                    scan += 1usize
                }
            }
            self.swap(greater, pivot)
            let equal_end = greater + 1usize
            if nth < lower {
                high = lower
            } else if nth >= equal_end {
                low = equal_end
            } else {
                break
            }
        }
        let base = mutable_data_pointer(mut self)
        let left = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base, nth)) }
        let middle = unsafe { base.add(nth) }
        let right = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawMut(middle.add(1usize), n - nth - 1usize))
        }
        (unsafe { mut *left }, unsafe { mut *middle }, unsafe { mut *right })
    }

    pub mut fn select_nth_unstable_by_key<K: Ord, F: mut fn(read T): K>(
        nth: usize,
        take key: F
    ): (mut [T] from self, mut T from self, mut [T] from self) {
        var key_fn = take key
        self.select_nth_unstable_by(nth, fn(read a: T, read b: T): Ordering {
            key_fn(a).cmp(key_fn(b))
        })
    }
}

fn linear_select<T, F: mut fn(read T, read T): bool>(
    mut xs: [T], start: usize, end: usize, nth: usize, mut less: F
): Unit {
    var low = start
    var high = end
    while high - low > 1usize {
        if high - low <= 5usize {
            var i = low + 1usize
            while i < high {
                var j = i
                while j > low && less(read xs[j], read xs[j - 1usize]) {
                    xs.swap(j, j - 1usize)
                    j -= 1usize
                }
                i += 1usize
            }
            return ()
        }
        var group = low
        var medians = 0usize
        while group < high {
            let stop = group + if high - group < 5usize { high - group } else { 5usize }
            var i = group + 1usize
            while i < stop {
                var j = i
                while j > group && less(read xs[j], read xs[j - 1usize]) {
                    xs.swap(j, j - 1usize)
                    j -= 1usize
                }
                i += 1usize
            }
            xs.swap(low + medians, group + (stop - group) / 2usize)
            medians += 1usize
            group = stop
        }
        let median = low + medians / 2usize
        linear_select(mut xs, low, low + medians, median, mut less)
        let pivot = high - 1usize
        xs.swap(median, pivot)
        var lower = low
        var scan = low
        var greater = pivot
        while scan < greater {
            if less(read xs[scan], read xs[pivot]) {
                xs.swap(scan, lower)
                lower += 1usize
                scan += 1usize
            } else if less(read xs[pivot], read xs[scan]) {
                greater -= 1usize
                xs.swap(scan, greater)
            } else {
                scan += 1usize
            }
        }
        xs.swap(greater, pivot)
        if nth < lower { high = lower }
        else if nth > greater { low = greater + 1usize }
        else { return () }
    }
}

// Introsort over `less`: median-of-three quicksort, insertion sort for short
// ranges and an in-place heapsort once the depth budget (2 * log2 n) is spent.
// Pending ranges live in a fixed stack; the smaller partition is pushed and the
// larger is processed next, so at most log2 n + 1 ranges are pending.
fn introsort<T, F: mut fn(read T, read T): bool>(mut xs: [T], take less: F) {
    var comparator = take less
    let n = xs.len()
    if n < 2usize { return }
    var budget = 0usize
    var shrinking = n
    while shrinking > 1usize { shrinking /= 2usize; budget += 2usize }
    var lows = [0usize; 80]
    var highs = [0usize; 80]
    var budgets = [0usize; 80]
    var top = 1usize
    lows[0usize] = 0usize
    highs[0usize] = n
    budgets[0usize] = budget
    while top > 0usize {
        top -= 1usize
        var lo = lows[top]
        var hi = highs[top]
        var left_budget = budgets[top]
        while hi - lo > 1usize {
            if hi - lo <= 16usize {
                var i = lo + 1usize
                while i < hi {
                    var j = i
                    while j > lo && comparator(read xs[j], read xs[j - 1usize]) {
                        xs.swap(j, j - 1usize)
                        j -= 1usize
                    }
                    i += 1usize
                }
                break
            }
            if left_budget == 0usize {
                let size = hi - lo
                var start = size / 2usize
                while start > 0usize {
                    start -= 1usize
                    var root = start
                    while true {
                        var child = root * 2usize + 1usize
                        if child >= size { break }
                        if child + 1usize < size && comparator(read xs[lo + child], read xs[lo + child + 1usize]) {
                            child += 1usize
                        }
                        if comparator(read xs[lo + root], read xs[lo + child]) {
                            xs.swap(lo + root, lo + child)
                            root = child
                        } else {
                            break
                        }
                    }
                }
                var end = size
                while end > 1usize {
                    end -= 1usize
                    xs.swap(lo, lo + end)
                    var root = 0usize
                    while true {
                        var child = root * 2usize + 1usize
                        if child >= end { break }
                        if child + 1usize < end && comparator(read xs[lo + child], read xs[lo + child + 1usize]) {
                            child += 1usize
                        }
                        if comparator(read xs[lo + root], read xs[lo + child]) {
                            xs.swap(lo + root, lo + child)
                            root = child
                        } else {
                            break
                        }
                    }
                }
                break
            }
            left_budget -= 1usize
            let mid = lo + (hi - lo) / 2usize
            let last = hi - 1usize
            if comparator(read xs[mid], read xs[lo]) { xs.swap(mid, lo) }
            if comparator(read xs[last], read xs[mid]) {
                xs.swap(last, mid)
                if comparator(read xs[mid], read xs[lo]) { xs.swap(mid, lo) }
            }
            xs.swap(lo, mid)
            var i = lo + 1usize
            var j = last
            while true {
                while i <= j && comparator(read xs[i], read xs[lo]) { i += 1usize }
                while i <= j && comparator(read xs[lo], read xs[j]) { j -= 1usize }
                if i >= j { break }
                xs.swap(i, j)
                i += 1usize
                j -= 1usize
            }
            xs.swap(lo, j)
            if j - lo < hi - (j + 1usize) {
                lows[top] = lo
                highs[top] = j
                budgets[top] = left_budget
                top += 1usize
                lo = j + 1usize
            } else {
                lows[top] = j + 1usize
                highs[top] = hi
                budgets[top] = left_budget
                top += 1usize
                hi = j
            }
        }
    }
}

// Borrowing iteration over the elements of a slice.
pub type SliceIter<region r, T> { items: read [T] from r; front: usize; back: usize }
extend<region r, T> SliceIter<region r, T> implements Iterator {
    type Item = read T from r
    fn size_hint(): (usize, usize?) {
        let count = self.back - self.front
        (count, present(count))
    }
    mut fn next(): (read T from r)? {
        if self.front < self.back {
            let i = self.front
            self.front += 1usize
            present(read self.items[i])
        } else {
            none
        }
    }
}
extend<region r, T> SliceIter<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read T from r)? {
        if self.front < self.back {
            self.back -= 1usize
            present(read self.items[self.back])
        } else {
            none
        }
    }
}

pub type SliceIterMut<region r, T> { items: mut [T] from r; front: usize; back: usize }
extend<region r, T> SliceIterMut<region r, T> implements Iterator {
    type Item = mut T from r
    fn size_hint(): (usize, usize?) {
        let count = self.back - self.front
        (count, present(count))
    }
    mut fn next(): (mut T from r)? {
        if self.front < self.back {
            let i = self.front
            self.front += 1usize
            present(mut self.items[i])
        } else {
            none
        }
    }
}
extend<region r, T> SliceIterMut<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (mut T from r)? {
        if self.front < self.back {
            self.back -= 1usize
            present(mut self.items[self.back])
        } else {
            none
        }
    }
}

extend<region r, T> SliceIter<region r, T> implements super.iter.ExactSizeIterator {}
extend<region r, T> SliceIter<region r, T> implements super.iter.FusedIterator {}
extend<region r, T> SliceIterMut<region r, T> implements super.iter.ExactSizeIterator {}
extend<region r, T> SliceIterMut<region r, T> implements super.iter.FusedIterator {}

extend<T> [T] {
    pub fn iter(): SliceIter<region self, T> { SliceIter(read self, 0usize, self.len()) }
    pub mut fn iter_mut(): SliceIterMut<region self, T> {
        let n = self.len()
        SliceIterMut(mut self, 0usize, n)
    }
}

extend<T> [T] implements Iterable {
    type Item = T
    type Iter<region r> = SliceIter<region r, T>
    fn iter<region r>(receiver read self: Self from r): SliceIter<region r, T> {
        self.iter()
    }
}

extend<T> [T] implements MutableIterable {
    type Item = T
    type IterMut<region r> = SliceIterMut<region r, T>
    fn iter_mut<region r>(receiver mut self: Self from r): SliceIterMut<region r, T> {
        self.iter_mut()
    }
}

// Copy-valued iteration over the bytes of a slice: yields `u8` while holding a
// read loan on the slice; allocates nothing.
pub type SliceBytes<region r> { items: read [u8] from r; front: usize; back: usize }
extend<region r> SliceBytes<region r> implements Iterator {
    type Item = u8
    mut fn next(): u8? {
        if self.front < self.back {
            let value = self.items[self.front]
            self.front += 1usize
            present(value)
        } else {
            none
        }
    }
}
extend<region r> SliceBytes<region r> implements BidirectionalIterator {
    mut fn next_back(): u8? {
        if self.front < self.back {
            self.back -= 1usize
            present(self.items[self.back])
        } else {
            none
        }
    }
}

extend [u8] {
    pub fn bytes(): SliceBytes<region self> { SliceBytes(read self, 0usize, self.len()) }
}

copy type RawRead<T> { data: ptr<read T>; len: usize }

// Safety: start <= end <= xs.len().
unsafe const fn sub<T>(read xs: [T], start: usize, end: usize): read [T] from xs {
    let fat = core.ptr.from_ref(xs)
    let raw = unsafe { core.mem.transmute<RawRead<T>>(fat) }
    let part = unsafe { core.mem.transmute<ptr<read [T]>>(RawRead(raw.data.add(start), end - start)) }
    unsafe { read *part }
}

// Safety: start <= end <= xs.len().
unsafe fn sub_mut<T>(mut xs: [T], start: usize, end: usize): mut [T] from xs {
    let base = mutable_data_pointer(mut xs)
    let part = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(start), end - start)) }
    unsafe { mut *part }
}

extend<T> [T] {
    // Safety: the caller guarantees `mid <= self.len()`.
    pub unsafe fn split_at_unchecked(
        mid: usize
    ): (read [T] from self, read [T] from self) {
        let n = self.len()
        (
            unsafe { sub<T>(read self, 0usize, mid) },
            unsafe { sub<T>(read self, mid, n) }
        )
    }

    pub fn split_at(mid: usize): (read [T] from self, read [T] from self) {
        if mid > self.len() { super.panic.panic("split index out of bounds") }
        (unsafe { sub<T>(read self, 0usize, mid) }, unsafe { sub<T>(read self, mid, self.len()) })
    }
    pub fn split_at_checked(mid: usize): (read [T] from self, read [T] from self)? {
        if mid > self.len() { return none }
        present((unsafe { sub<T>(read self, 0usize, mid) }, unsafe { sub<T>(read self, mid, self.len()) }))
    }
    pub mut fn split_at_mut(mid: usize): (mut [T] from self, mut [T] from self) {
        if mid > self.len() { super.panic.panic("split index out of bounds") }
        let n = self.len()
        let base = mutable_data_pointer(mut self)
        // The guard keeps both ranges within the initialized slice and disjoint.
        let left = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base, mid)) }
        let right = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(mid), n - mid)) }
        (unsafe { mut *left }, unsafe { mut *right })
    }

    // Safety: the caller guarantees `mid <= self.len()`.
    pub mut unsafe fn split_at_mut_unchecked(
        mid: usize
    ): (mut [T] from self, mut [T] from self) {
        let n = self.len()
        let base = mutable_data_pointer(mut self)
        let left = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawMut(base, mid))
        }
        let right = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(mid), n - mid))
        }
        // The caller-established boundary makes these views disjoint.
        (unsafe { mut *left }, unsafe { mut *right })
    }

    pub mut const fn split_at_mut_checked(mid: usize): (mut [T] from self, mut [T] from self)? {
        if mid > self.len() { return none }
        let n = self.len()
        let base = mutable_data_pointer(mut self)
        // The guard keeps both ranges within the initialized slice and disjoint.
        let left = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base, mid)) }
        let right = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(mid), n - mid)) }
        present((unsafe { mut *left }, unsafe { mut *right }))
    }

    pub fn split_first(): (read T from self, read [T] from self)? {
        if self.len() == 0usize { return none }
        present((read self[0usize], unsafe { sub<T>(read self, 1usize, self.len()) }))
    }
    pub fn split_last(): (read T from self, read [T] from self)? {
        let n = self.len()
        if n == 0usize { return none }
        present((read self[n - 1usize], unsafe { sub<T>(read self, 0usize, n - 1usize) }))
    }
    pub mut fn split_first_mut(): (mut T from self, mut [T] from self)? {
        let n = self.len()
        if n == 0usize { return none }
        let base = mutable_data_pointer(mut self)
        let tail = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(1usize), n - 1usize)) }
        present((unsafe { mut *base }, unsafe { mut *tail }))
    }
    pub mut fn split_last_mut(): (mut T from self, mut [T] from self)? {
        let n = self.len()
        if n == 0usize { return none }
        let base = mutable_data_pointer(mut self)
        let last = unsafe { base.add(n - 1usize) }
        let head = unsafe { core.mem.transmute<ptr<mut [T]>>(RawMut(base, n - 1usize)) }
        present((unsafe { mut *last }, unsafe { mut *head }))
    }

    pub mut fn rotate_left(mid: usize): Unit {
        let n = self.len()
        if mid > n { super.panic.panic("rotation index out of bounds") }
        if mid == 0usize || mid == n { return () }
        var left = 0usize
        var right = mid
        while left + 1usize < right {
            right -= 1usize
            self.swap(left, right)
            left += 1usize
        }
        left = mid
        right = n
        while left + 1usize < right {
            right -= 1usize
            self.swap(left, right)
            left += 1usize
        }
        left = 0usize
        right = n
        while left + 1usize < right {
            right -= 1usize
            self.swap(left, right)
            left += 1usize
        }
    }
    pub mut fn rotate_right(mid: usize): Unit {
        let n = self.len()
        if mid > n { super.panic.panic("rotation index out of bounds") }
        if mid == 0usize || mid == n { return () }
        self.rotate_left(n - mid)
    }
}

extend<T: Copy> [T] {
    pub mut fn fill(value: T) {
        var i = 0usize
        while i < self.len() {
            self[i] = value
            i += 1usize
        }
    }
    // Panics when the lengths differ.
    pub mut fn copy_from_slice(read source: [T]) {
        if source.len() != self.len() { super.panic.panic("copy_from_slice length mismatch") }
        var i = 0usize
        while i < source.len() {
            self[i] = source[i]
            i += 1usize
        }
    }
    pub mut fn copy_within(start: usize, end: usize, destination: usize): Unit {
        let n = self.len()
        if start > end || end > n { super.panic.panic("copy range out of bounds") }
        let count = end - start
        if destination > n || count > n - destination {
            super.panic.panic("copy destination out of bounds")
        }
        if destination < start {
            var i = 0usize
            while i < count {
                self[destination + i] = self[start + i]
                i += 1usize
            }
        } else {
            var i = count
            while i > 0usize {
                i -= 1usize
                self[destination + i] = self[start + i]
            }
        }
    }
}

extend<T> [T] {
    pub mut fn fill_with<F: mut fn(): T>(take generate: F): Unit {
        var generator = take generate
        var i = 0usize
        while i < self.len() {
            self[i] = generator()
            i += 1usize
        }
    }
    pub mut fn swap_with_slice(mut other: [T]): Unit {
        if other.len() != self.len() { super.panic.panic("swap_with_slice length mismatch") }
        let left = mutable_data_pointer(mut self)
        let right = mutable_data_pointer(mut other)
        var i = 0usize
        while i < self.len() {
            unsafe { core.ptr.swap(left.add(i), right.add(i)) }
            i += 1usize
        }
    }
}

extend<T: Clone> [T] {
    pub mut fn clone_from_slice(read source: [T]): Unit {
        if source.len() != self.len() { super.panic.panic("clone_from_slice length mismatch") }
        var i = 0usize
        while i < source.len() {
            self[i] = source[i].clone()
            i += 1usize
        }
    }
}

extend<T> [T] {
    pub fn subslice(start: usize, end: usize): (read [T] from self)? {
        if start <= end && end <= self.len() { present(unsafe { sub<T>(read self, start, end) }) } else { none }
    }
    // The `index`-th window of `size` overlapping elements, if it exists.
    pub fn window(index: usize, size: usize): (read [T] from self)? {
        if size == 0usize || index > self.len() || size > self.len() - index { return none }
        self.subslice(index, index + size)
    }
    // The `index`-th chunk of `size` elements; the last chunk may be shorter.
    pub fn chunk(index: usize, size: usize): (read [T] from self)? {
        if size == 0usize { return none }
        if self.len() == 0usize || index > (self.len() - 1usize) / size { return none }
        let start = index * size
        let end = if self.len() - start < size { self.len() } else { start + size }
        self.subslice(start, end)
    }
    pub fn chunks(size: usize): SliceChunks<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        SliceChunks(read self, size, 0usize, self.len())
    }
    pub fn chunks_exact(size: usize): SliceChunksExact<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let remainder = n % size
        let back = n - remainder
        SliceChunksExact(read self, size, 0usize, back, back)
    }
    pub fn rchunks(size: usize): SliceRChunks<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        SliceRChunks(read self, size, 0usize, self.len())
    }
    pub fn rchunks_exact(size: usize): SliceRChunksExact<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let remainder = n % size
        SliceRChunksExact(read self, size, remainder, n, remainder)
    }
    pub fn windows(size: usize): SliceWindows<region self, T> {
        if size == 0usize { super.panic.panic("window size must be nonzero") }
        let n = self.len()
        let count = if size > n { 0usize } else { n - size + 1usize }
        SliceWindows(read self, size, 0usize, count)
    }
    pub fn array_windows<const N: usize>(): SliceArrayWindows<region self, T, N> {
        if N == 0usize { super.panic.panic("window size must be nonzero") }
        let n = self.len()
        let count = if N > n { 0usize } else { n - N + 1usize }
        SliceArrayWindows(read self, 0usize, count)
    }
}

pub type SliceChunks<region r, T> {
    items: read [T] from r
    size: usize
    front: usize
    back: usize
}
extend<region r, T> SliceChunks<region r, T> implements Iterator {
    type Item = read [T] from r
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        let full = remaining / self.size
        let count = if remaining % self.size == 0usize { full } else { full + 1usize }
        (count, present(count))
    }
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        let count = if self.back - start < self.size { self.back - start } else { self.size }
        self.front += count
        present(unsafe { sub<T>(self.items, start, start + count) })
    }
}
extend<region r, T> SliceChunks<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.front == self.back { return none }
        let remaining = self.back - self.front
        let remainder = remaining % self.size
        let count = if remainder == 0usize { self.size } else { remainder }
        let start = self.back - count
        self.back = start
        present(unsafe { sub<T>(self.items, start, start + count) })
    }
}
extend<region r, T> SliceChunks<region r, T> implements Clone {
    fn clone(): SliceChunks<region r, T> {
        SliceChunks(self.items, self.size, self.front, self.back)
    }
}
extend<region r, T: fmt.Debug> SliceChunks<region r, T> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_tuple("Chunks")
        var start = self.front
        while start < self.back {
            let count = if self.back - start < self.size {
                self.back - start
            } else {
                self.size
            }
            try debug.field(self.items.window(start, count).unwrap())
            start += count
        }
        try debug.finish()
    }
}

pub type SliceWindows<region r, T> {
    items: read [T] from r
    size: usize
    front: usize
    back: usize
}
extend<region r, T> SliceWindows<region r, T> implements Iterator {
    type Item = read [T] from r
    fn size_hint(): (usize, usize?) {
        let count = self.back - self.front
        (count, present(count))
    }
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        self.front += 1usize
        present(unsafe { sub<T>(self.items, start, start + self.size) })
    }
}
extend<region r, T> SliceWindows<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.front == self.back { return none }
        self.back -= 1usize
        present(unsafe { sub<T>(self.items, self.back, self.back + self.size) })
    }
}
extend<region r, T> SliceWindows<region r, T> implements Clone {
    fn clone(): SliceWindows<region r, T> {
        SliceWindows(self.items, self.size, self.front, self.back)
    }
}
extend<region r, T: fmt.Debug> SliceWindows<region r, T> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_tuple("Windows")
        var index = self.front
        while index < self.back {
            try debug.field(self.items.window(index, self.size).unwrap())
            index += 1usize
        }
        try debug.finish()
    }
}
extend<region r, T> SliceChunks<region r, T> implements super.iter.ExactSizeIterator {}
extend<region r, T> SliceWindows<region r, T> implements super.iter.ExactSizeIterator {}

pub type SliceArrayWindows<region r, T, const N: usize> {
    items: read [T] from r
    front: usize
    back: usize
}
extend<region r, T, const N: usize> SliceArrayWindows<region r, T, N> implements Iterator {
    type Item = read [T; N] from r
    fn size_hint(): (usize, usize?) {
        let count = self.back - self.front
        (count, present(count))
    }
    mut fn next(): (read [T; N] from r)? {
        if self.front == self.back { return none }
        let index = self.front
        self.front += 1usize
        present(self.items.window(index, N).unwrap().as_array<N>().unwrap())
    }
}
extend<region r, T, const N: usize> SliceArrayWindows<region r, T, N> implements BidirectionalIterator {
    mut fn next_back(): (read [T; N] from r)? {
        if self.front == self.back { return none }
        self.back -= 1usize
        present(self.items.window(self.back, N).unwrap().as_array<N>().unwrap())
    }
}
extend<region r, T, const N: usize> SliceArrayWindows<region r, T, N> implements super.iter.ExactSizeIterator {}
extend<region r, T, const N: usize> SliceArrayWindows<region r, T, N> implements super.iter.FusedIterator {}

pub type SliceChunksMut<region r, T> {
    items: mut [T] from r
    size: usize
    front: usize
    back: usize
}
extend<region r, T> SliceChunksMut<region r, T> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        let count = if self.back - start < self.size { self.back - start } else { self.size }
        self.front += count
        present(unsafe { sub_mut<T>(mut *self.items, start, start + count) })
    }
}
extend<region r, T> SliceChunksMut<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let remaining = self.back - self.front
        let remainder = remaining % self.size
        let count = if remainder == 0usize { self.size } else { remainder }
        let start = self.back - count
        self.back = start
        present(unsafe { sub_mut<T>(mut *self.items, start, start + count) })
    }
}

extend<T> [T] {
    pub mut fn chunks_mut(size: usize): SliceChunksMut<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        SliceChunksMut(mut self, size, 0usize, n)
    }
    pub mut fn chunks_exact_mut(size: usize): SliceChunksExactMut<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let remainder = n % size
        let back = n - remainder
        SliceChunksExactMut(mut self, size, 0usize, back, back)
    }
    pub mut fn rchunks_mut(size: usize): SliceRChunksMut<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        SliceRChunksMut(mut self, size, 0usize, n)
    }
    pub mut fn rchunks_exact_mut(size: usize): SliceRChunksExactMut<region self, T> {
        if size == 0usize { super.panic.panic("chunk size must be nonzero") }
        let n = self.len()
        let remainder = n % size
        SliceRChunksExactMut(mut self, size, remainder, n, remainder)
    }
}

extend<T> [T] {
    pub mut const fn first_chunk_mut<const N: usize>(): (mut [T; N] from self)? {
        if N > self.len() { return none }
        let base = mutable_data_pointer(mut self)
        // Safety: the checked array is in-bounds and the receiver is exclusive.
        present(unsafe { mut *base.cast<[T; N]>() })
    }

    pub mut const fn last_chunk_mut<const N: usize>(): (mut [T; N] from self)? {
        if N > self.len() { return none }
        let base = mutable_data_pointer(mut self)
        // Safety: the checked suffix is in-bounds and the receiver is exclusive.
        present(unsafe { mut *base.add(self.len() - N).cast<[T; N]>() })
    }

    pub mut const fn split_first_chunk_mut<const N: usize>(): ((mut [T; N] from self), (mut [T] from self))? {
        if N > self.len() { return none }
        let n = self.len()
        let base = mutable_data_pointer(mut self)
        let first = base.cast<[T; N]>()
        let rest = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawMut(base.add(N), n - N))
        }
        // Safety: these two checked ranges are disjoint parts of the exclusive slice.
        present((unsafe { mut *first }, unsafe { mut *rest }))
    }

    pub mut const fn split_last_chunk_mut<const N: usize>(): ((mut [T] from self), (mut [T; N] from self))? {
        if N > self.len() { return none }
        let n = self.len()
        let start = n - N
        let base = mutable_data_pointer(mut self)
        let rest = unsafe {
            core.mem.transmute<ptr<mut [T]>>(RawMut(base, start))
        }
        let last = unsafe { base.add(start).cast<[T; N]>() }
        // Safety: these two checked ranges are disjoint parts of the exclusive slice.
        present((unsafe { mut *rest }, unsafe { mut *last }))
    }
}

extend<T> [T] {
    pub fn split<F: mut fn(read T): bool>(take test: F): SliceSplit<region self, T, F> {
        SliceSplit(read self, test, 0usize, self.len(), 0xffffffffffffffffusize, false, false, false, false)
    }
    pub fn splitn<F: mut fn(read T): bool>(count: usize, take test: F): SliceSplitN<region self, T, F> {
        SliceSplitN(SliceSplit(read self, test, 0usize, self.len(), count, false, false, false, false))
    }
    pub fn rsplitn<F: mut fn(read T): bool>(count: usize, take test: F): SliceSplitN<region self, T, F> {
        SliceSplitN(SliceSplit(read self, test, 0usize, self.len(), count, true, false, false, false))
    }
    pub fn rsplit<F: mut fn(read T): bool>(take test: F): super.iter.Reversed<SliceSplit<region self, T, F>> {
        self.split(test).rev()
    }
    pub fn split_inclusive<F: mut fn(read T): bool>(
        take test: F
    ): SliceSplit<region self, T, F> {
        SliceSplit(read self, test, 0usize, self.len(), 0xffffffffffffffffusize, false, true, false, false)
    }
    pub mut fn split_mut<F: mut fn(read T): bool>(
        take test: F
    ): SliceSplitMut<region self, T, F> {
        let n = self.len()
        SliceSplitMut(
            mut self, test, 0usize, n, false, false, false,
            0xffffffffffffffffusize, false
        )
    }
    pub mut fn splitn_mut<F: mut fn(read T): bool>(
        count: usize,
        take test: F
    ): SliceSplitMut<region self, T, F> {
        let n = self.len()
        SliceSplitMut(
            mut self, test, 0usize, n, false, false, false, count, false
        )
    }
    pub mut fn rsplit_mut<F: mut fn(read T): bool>(
        take test: F
    ): SliceSplitMut<region self, T, F> {
        let n = self.len()
        SliceSplitMut(
            mut self, test, 0usize, n, false, false, false,
            0xffffffffffffffffusize, true
        )
    }
    pub mut fn rsplitn_mut<F: mut fn(read T): bool>(
        count: usize,
        take test: F
    ): SliceSplitMut<region self, T, F> {
        let n = self.len()
        SliceSplitMut(
            mut self, test, 0usize, n, false, false, false, count, true
        )
    }
    pub mut fn split_inclusive_mut<F: mut fn(read T): bool>(
        take test: F
    ): SliceSplitMut<region self, T, F> {
        let n = self.len()
        SliceSplitMut(
            mut self, test, 0usize, n, true, false, false,
            0xffffffffffffffffusize, false
        )
    }
    pub fn chunk_by<F: mut fn(read T, read T): bool>(
        take same: F
    ): SliceChunkBy<region self, T, F> {
        SliceChunkBy(read self, same, 0usize, self.len())
    }
    pub mut fn chunk_by_mut<F: mut fn(read T, read T): bool>(
        take same: F
    ): SliceChunkByMut<region self, T, F> {
        let n = self.len()
        SliceChunkByMut(mut self, same, 0usize, n)
    }
}

pub type SliceChunksExact<region r, T> {
    items: read [T] from r
    size: usize
    front: usize
    back: usize
    remainder_start: usize
}
extend<region r, T> SliceChunksExact<region r, T> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        self.front += self.size
        present(unsafe { sub<T>(self.items, start, self.front) })
    }
}
extend<region r, T> SliceChunksExact<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.front == self.back { return none }
        self.back -= self.size
        present(unsafe { sub<T>(self.items, self.back, self.back + self.size) })
    }
}
extend<region r, T> SliceChunksExact<region r, T> {
    pub fn remainder(): read [T] from r {
        unsafe { sub<T>(self.items, self.remainder_start, self.items.len()) }
    }
}

pub type SliceRChunks<region r, T> {
    items: read [T] from r
    size: usize
    front: usize
    back: usize
}
extend<region r, T> SliceRChunks<region r, T> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        let count = if self.back - self.front < self.size { self.back - self.front } else { self.size }
        self.back -= count
        present(unsafe { sub<T>(self.items, self.back, self.back + count) })
    }
}
extend<region r, T> SliceRChunks<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.front == self.back { return none }
        let remaining = self.back - self.front
        let remainder = remaining % self.size
        let count = if remainder == 0usize { self.size } else { remainder }
        let start = self.front
        self.front += count
        present(unsafe { sub<T>(self.items, start, self.front) })
    }
}

pub type SliceRChunksExact<region r, T> {
    items: read [T] from r
    size: usize
    front: usize
    back: usize
    remainder_end: usize
}
extend<region r, T> SliceRChunksExact<region r, T> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        self.back -= self.size
        present(unsafe { sub<T>(self.items, self.back, self.back + self.size) })
    }
}
extend<region r, T> SliceRChunksExact<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        self.front += self.size
        present(unsafe { sub<T>(self.items, start, self.front) })
    }
}
extend<region r, T> SliceRChunksExact<region r, T> {
    pub fn remainder(): read [T] from r {
        unsafe { sub<T>(self.items, 0usize, self.remainder_end) }
    }
}

pub type SliceChunksExactMut<region r, T> {
    items: mut [T] from r
    size: usize
    front: usize
    back: usize
    remainder_start: usize
}
extend<region r, T> SliceChunksExactMut<region r, T> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        self.front += self.size
        present(unsafe { sub_mut<T>(mut *self.items, start, self.front) })
    }
}
extend<region r, T> SliceChunksExactMut<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (mut [T] from r)? {
        if self.front == self.back { return none }
        self.back -= self.size
        present(unsafe { sub_mut<T>(mut *self.items, self.back, self.back + self.size) })
    }
}
extend<region r, T> SliceChunksExactMut<region r, T> {
    pub mut fn remainder(): mut [T] from r {
        let n = self.items.len()
        unsafe { sub_mut<T>(mut *self.items, self.remainder_start, n) }
    }
}

pub type SliceRChunksMut<region r, T> {
    items: mut [T] from r
    size: usize
    front: usize
    back: usize
}
extend<region r, T> SliceRChunksMut<region r, T> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let count = if self.back - self.front < self.size { self.back - self.front } else { self.size }
        self.back -= count
        present(unsafe { sub_mut<T>(mut *self.items, self.back, self.back + count) })
    }
}
extend<region r, T> SliceRChunksMut<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let remaining = self.back - self.front
        let remainder = remaining % self.size
        let count = if remainder == 0usize { self.size } else { remainder }
        let start = self.front
        self.front += count
        present(unsafe { sub_mut<T>(mut *self.items, start, self.front) })
    }
}

pub type SliceRChunksExactMut<region r, T> {
    items: mut [T] from r
    size: usize
    front: usize
    back: usize
    remainder_end: usize
}
extend<region r, T> SliceRChunksExactMut<region r, T> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.front == self.back { return none }
        self.back -= self.size
        present(unsafe { sub_mut<T>(mut *self.items, self.back, self.back + self.size) })
    }
}
extend<region r, T> SliceRChunksExactMut<region r, T> implements BidirectionalIterator {
    mut fn next_back(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        self.front += self.size
        present(unsafe { sub_mut<T>(mut *self.items, start, self.front) })
    }
}
extend<region r, T> SliceRChunksExactMut<region r, T> {
    pub mut fn remainder(): mut [T] from r {
        unsafe { sub_mut<T>(mut *self.items, 0usize, self.remainder_end) }
    }
}

pub type SliceSplitN<region r, T, F> { inner: SliceSplit<region r, T, F> }
extend<region r, T, F: mut fn(read T): bool> SliceSplitN<region r, T, F> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? { self.inner.next() }
}

pub type SliceSplit<region r, T, F> {
    items: read [T] from r
    test: F
    front: usize
    back: usize
    remaining: usize
    from_back: bool
    inclusive: bool
    suppress_empty_tail: bool
    done: bool
}
extend<region r, T, F: mut fn(read T): bool> SliceSplit<region r, T, F> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.done || self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.front == self.back {
            if self.inclusive {
                self.done = true
                return none
            }
            self.done = true
            return present(unsafe { sub<T>(self.items, self.front, self.back) })
        }
        if self.remaining == 0usize {
            self.done = true
            return present(unsafe { sub<T>(self.items, self.front, self.back) })
        }
        if self.from_back {
            var i = self.back
            while i > self.front {
                i -= 1usize
                if self.test(read self.items[i]) {
                    let start = i + 1usize
                    let part = unsafe { sub<T>(self.items, start, self.back) }
                    self.back = i
                    return present(part)
                }
            }
            self.done = true
            return present(unsafe { sub<T>(self.items, self.front, self.back) })
        }
        var i = self.front
        while i < self.back {
            if self.test(read self.items[i]) {
                let end = if self.inclusive { i + 1usize } else { i }
                let part = unsafe { sub<T>(self.items, self.front, end) }
                self.front = i + 1usize
                if self.inclusive && self.front == self.back {
                    self.suppress_empty_tail = true
                }
                return present(part)
            }
            i += 1usize
        }
        self.done = true
        present(unsafe { sub<T>(self.items, self.front, self.back) })
    }
}
extend<region r, T, F: mut fn(read T): bool> SliceSplit<region r, T, F> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.done || self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.front == self.back {
            if self.inclusive {
                self.done = true
                return none
            }
            self.done = true
            return present(unsafe { sub<T>(self.items, self.front, self.back) })
        }
        if self.remaining == 0usize {
            self.done = true
            return present(unsafe { sub<T>(self.items, self.front, self.back) })
        }
        var i = self.back
        while i > self.front {
            i -= 1usize
            if self.test(read self.items[i]) {
                if self.inclusive {
                    if i + 1usize == self.back { continue }
                    let start = i + 1usize
                    let part = unsafe { sub<T>(self.items, start, self.back) }
                    self.back = start
                    return present(part)
                }
                let start = i + 1usize
                let part = unsafe { sub<T>(self.items, start, self.back) }
                self.back = i
                return present(part)
            }
        }
        self.done = true
        present(unsafe { sub<T>(self.items, self.front, self.back) })
    }
}

pub type SliceSplitMut<region r, T, F> {
    items: mut [T] from r
    test: F
    front: usize
    back: usize
    inclusive: bool
    suppress_empty_tail: bool
    done: bool
    remaining: usize
    from_back: bool
}
extend<region r, T, F: mut fn(read T): bool> SliceSplitMut<region r, T, F> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.done || self.remaining == 0usize { return none }
        self.remaining -= 1usize
        if self.front == self.back {
            if self.inclusive {
                self.done = true
                return none
            }
            self.done = true
            return present(unsafe { sub_mut<T>(mut *self.items, self.front, self.back) })
        }
        if self.remaining == 0usize {
            self.done = true
            return present(unsafe { sub_mut<T>(mut *self.items, self.front, self.back) })
        }
        let base = mutable_data_pointer(mut *self.items)
        if self.from_back {
            var i = self.back
            while i > self.front {
                i -= 1usize
                if self.test(unsafe { read *base.add(i) }) {
                    let start = i + 1usize
                    let part = unsafe { sub_mut<T>(mut *self.items, start, self.back) }
                    self.back = i
                    return present(part)
                }
            }
            self.done = true
            return present(unsafe { sub_mut<T>(mut *self.items, self.front, self.back) })
        }
        var i = self.front
        while i < self.back {
            if self.test(unsafe { read *base.add(i) }) {
                let end = if self.inclusive { i + 1usize } else { i }
                let part = unsafe { sub_mut<T>(mut *self.items, self.front, end) }
                self.front = i + 1usize
                if self.inclusive && self.front == self.back {
                    self.suppress_empty_tail = true
                }
                return present(part)
            }
            i += 1usize
        }
        self.done = true
        present(unsafe { sub_mut<T>(mut *self.items, self.front, self.back) })
    }
}

pub type SliceChunkBy<region r, T, F> {
    items: read [T] from r
    same: F
    front: usize
    back: usize
}
extend<region r, T, F: mut fn(read T, read T): bool> SliceChunkBy<region r, T, F> implements Iterator {
    type Item = read [T] from r
    mut fn next(): (read [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        var end = start + 1usize
        while end < self.back && self.same(read self.items[end - 1usize], read self.items[end]) {
            end += 1usize
        }
        self.front = end
        present(unsafe { sub<T>(self.items, start, end) })
    }
}
extend<region r, T, F: mut fn(read T, read T): bool> SliceChunkBy<region r, T, F> implements BidirectionalIterator {
    mut fn next_back(): (read [T] from r)? {
        if self.front == self.back { return none }
        let end = self.back
        var start = end - 1usize
        while start > self.front && self.same(read self.items[start - 1usize], read self.items[start]) {
            start -= 1usize
        }
        self.back = start
        present(unsafe { sub<T>(self.items, start, end) })
    }
}

pub type SliceChunkByMut<region r, T, F> {
    items: mut [T] from r
    same: F
    front: usize
    back: usize
}
extend<region r, T, F: mut fn(read T, read T): bool> SliceChunkByMut<region r, T, F> implements Iterator {
    type Item = mut [T] from r
    mut fn next(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let start = self.front
        var end = start + 1usize
        let base = mutable_data_pointer(mut *self.items)
        while end < self.back && self.same(
            unsafe { read *base.add(end - 1usize) },
            unsafe { read *base.add(end) }
        ) {
            end += 1usize
        }
        self.front = end
        present(unsafe { sub_mut<T>(mut *self.items, start, end) })
    }
}
extend<region r, T, F: mut fn(read T, read T): bool> SliceChunkByMut<region r, T, F> implements BidirectionalIterator {
    mut fn next_back(): (mut [T] from r)? {
        if self.front == self.back { return none }
        let end = self.back
        let base = mutable_data_pointer(mut *self.items)
        var start = end - 1usize
        while start > self.front && self.same(
            unsafe { read *base.add(start - 1usize) },
            unsafe { read *base.add(start) }
        ) {
            start -= 1usize
        }
        self.back = start
        present(unsafe { sub_mut<T>(mut *self.items, start, end) })
    }
}

extend<region r, T> SliceIterMut<region r, T> {
    pub fn into_slice(receiver take self: Self): mut [T] from r {
        unsafe { sub_mut<T>(mut *self.items, self.front, self.back) }
    }
}

extend<T, const N: usize> [T; N] {
    pub fn each_ref<region r>(
        receiver read self: Self from r
    ): [read T from r; N] from r {
        var result = core.mem.MaybeUninit<[read T from r; N]>.uninit()
        let slots = core.ptr.from_mut(result).cast<core.mem.MaybeUninit<read T from r>>()
        let base = core.ptr.from_ref(self).cast<T>()
        var i = 0usize
        // Safety: every slot and every source element is in bounds.
        while i < N {
            unsafe { mut *slots.add(i) }.write(unsafe { read *base.add(i) })
            i += 1usize
        }
        // Safety: every element of the result array was initialized above.
        unsafe { result.assume_init() }
    }

    pub fn each_mut<region r>(
        receiver mut self: Self from r
    ): [mut T from r; N] from r {
        var result = core.mem.MaybeUninit<[mut T from r; N]>.uninit()
        let slots = core.ptr.from_mut(result).cast<core.mem.MaybeUninit<mut T from r>>()
        let base = core.ptr.from_mut(self).cast<T>()
        var i = 0usize
        // Safety: every slot and source element is in bounds; distinct indices
        // create disjoint mutable views that remain within the source array.
        while i < N {
            unsafe { mut *slots.add(i) }.write(unsafe { mut *base.add(i) })
            i += 1usize
        }
        // Safety: every element of the result array was initialized above.
        unsafe { result.assume_init() }
    }
}

extend<T, const N: usize> [T; N] {
    pub fn len(): usize { N }
    pub fn is_empty(): bool { N == 0usize }
    pub fn as_slice(): read [T] from self { read self }
    pub mut fn as_mut_slice(): mut [T] from self { mut self }
}
extend<T, const N: usize> [T; N] implements AsRef<[T]> {
    fn as_ref(): read [T] from self { read self }
}
extend<T, const N: usize> [T; N] implements Borrow<[T]> {
    fn borrow(): read [T] from self { read self }
}
extend<T, const N: usize> [T; N] implements BorrowMut<[T]> {
    mut fn borrow_mut(): mut [T] from self { mut self }
}
extend<T, const N: usize> [T; N] implements AsMut<[T]> {
    mut fn as_mut(): mut [T] from self { mut self }
}
extend<T, const N: usize> [T; N] implements Index<usize> {
    type Output = T
    fn index(read index: usize): read T from self { read self[index] }
}
extend<T, const N: usize> [T; N] implements IndexMut<usize> {
    type Output = T
    mut fn index_mut(read index: usize): mut T from self { mut self[index] }
}
extend<T> [T] implements Index<usize> {
    type Output = T
    fn index(read index: usize): read T from self { read self[index] }
}
extend<T> [T] implements IndexMut<usize> {
    type Output = T
    mut fn index_mut(read index: usize): mut T from self { mut self[index] }
}
pub copy enum GetDisjointMutError { IndexOutOfBounds, OverlappingIndices }

extend<T> [T] {
    pub mut fn get_disjoint_mut<const N: usize>(
        read indices: [usize; N]
    ): [mut T from self; N] from self throws GetDisjointMutError {
        var i = 0usize
        while i < N {
            if indices[i] >= self.len() { throw GetDisjointMutError.IndexOutOfBounds }
            var j = 0usize
            while j < i {
                if indices[j] == indices[i] { throw GetDisjointMutError.OverlappingIndices }
                j += 1usize
            }
            i += 1usize
        }
        var result = core.mem.MaybeUninit<[mut T from self; N] from self>.uninit()
        let slots = core.ptr.from_mut(result).cast<core.mem.MaybeUninit<mut T from self>>()
        let base = mutable_data_pointer(mut self)
        i = 0usize
        // Safety: indices are in bounds and pairwise distinct, so every view is disjoint.
        while i < N {
            unsafe { mut *slots.add(i) }.write(unsafe { mut *base.add(indices[i]) })
            i += 1usize
        }
        // Safety: every element of the result array was initialized above.
        unsafe { result.assume_init() }
    }

    // Safety: every index is in bounds and all indices are pairwise distinct.
    pub mut unsafe fn get_disjoint_unchecked_mut<const N: usize>(
        read indices: [usize; N]
    ): [mut T from self; N] from self {
        var result = core.mem.MaybeUninit<[mut T from self; N] from self>.uninit()
        let slots = core.ptr.from_mut(result).cast<core.mem.MaybeUninit<mut T from self>>()
        let base = mutable_data_pointer(mut self)
        var i = 0usize
        // Safety: the caller guarantees in-bounds distinct indices.
        while i < N {
            unsafe { mut *slots.add(i) }.write(unsafe { mut *base.add(indices[i]) })
            i += 1usize
        }
        // Safety: every element of the result array was initialized above.
        unsafe { result.assume_init() }
    }

}

extend<T, const N: usize> [T; N] implements Iterable {
    type Item = T
    type Iter<region r> = SliceIter<region r, T>
    fn iter<region r>(receiver read self: Self from r): SliceIter<region r, T> {
        let items: read [T] from r = read self
        items.iter()
    }
}
extend<T, const N: usize> [T; N] implements MutableIterable {
    type Item = T
    type IterMut<region r> = SliceIterMut<region r, T>
    fn iter_mut<region r>(receiver mut self: Self from r): SliceIterMut<region r, T> {
        let items: mut [T] from r = mut self
        items.iter_mut()
    }
}
