import core.iter.{Iterator, BidirectionalIterator, ExactSizeIterator, FusedIterator, OwnedIterable, Iterable, MutableIterable, FromItems, ExtendItems}
import core.clone.Clone
import core.default.Default
import core.cmp.Eq
import core.fmt
import super.alloc.{Allocator, Global, AllocError, Layout, layout_unchecked, free_block, handle_alloc_error, layout_of, dangling_for}
import super.collections.TryReserveError
import core.hash.{BuildHasher, Hash, Hasher, SipHasher, sip13}
import core.cmp.PartialEq
import core.borrow.KeyView
import core.ops.{BitAnd, BitOr, BitXor, Sub}

pub type Bucket<K, V> {
    pub key: K
    pub value: V
}

fn table_limit(cap: usize): usize { cap - cap / 8usize }

fn array_layout(element: Layout, count: usize): Layout throws TryReserveError {
    let bytes = match count.checked_mul(element.size()) {
        present(bytes) => bytes,
        none => throw TryReserveError.capacity_overflow()
    }
    if bytes > isize.MAX as usize - (element.align() - 1usize) {
        throw TryReserveError.capacity_overflow()
    }
    unsafe { layout_unchecked(bytes, element.align()) }
}

@inline(never)
fn rebuild_layouts(bucket: Layout, capacity: usize, count: usize): (Layout, Layout, Layout) throws TryReserveError {
    let payload = try array_layout(bucket, capacity)
    let control = try array_layout(layout_of<u8>(), if capacity == 0usize { 0usize } else { capacity + 16usize })
    let hashes = try array_layout(layout_of<u64>(), count)
    (payload, control, hashes)
}

@inline(never)
fn allocate_rebuild_block<A: Allocator>(mut allocator: A, layout: Layout, dangling: ptr<mut u8>): ptr<mut u8> throws TryReserveError {
    if layout.size() == 0usize { return dangling }
    match capture allocator.allocate(layout) {
        success(p) => p,
        failure(_) => throw TryReserveError.allocation_error(layout)
    }
}

fn set_control(controls: ptr<mut u8>, cap: usize, index: usize, tag: u8): Unit {
    unsafe {
        *controls.add(index) = tag
        if index < 16usize {
            *controls.add(cap + index) = tag
            if cap == 8usize { *controls.add(16usize + index) = tag }
        }
    }
}

@inline(never)
fn vacant_slot(controls: ptr<mut u8>, cap: usize, hash: u64): usize {
    let mask = cap - 1usize
    var start = (hash as usize) & mask
    var step = 0usize
    while true {
        var lane = 0usize
        while lane < 16usize {
            let index = (start + lane) & mask
            if unsafe { *controls.add(index) >= 128u8 } { return index }
            lane += 1usize
        }
        step += 16usize
        start = (start + step) & mask
    }
    0usize
}

@inline(never)
unsafe fn move_rebuild_entries(
    old_payload: ptr<read u8>, old_controls: ptr<read u8>, old_cap: usize,
    new_payload: ptr<mut u8>, new_controls: ptr<mut u8>, new_cap: usize,
    hashes: ptr<read u64>, size: usize
): Unit {
    var ordinal = 0usize
    var i = 0usize
    while i < old_cap {
        if unsafe { *old_controls.add(i) < 128u8 } {
            let hash = unsafe { *hashes.add(ordinal) }
            let index = vacant_slot(new_controls, new_cap, hash)
            if size != 0usize {
                unsafe {
                    core.ptr.copy_nonoverlapping(old_payload.add(i * size), new_payload.add(index * size), size)
                }
            }
            set_control(new_controls, new_cap, index, (hash >> 57u64) as u8)
            ordinal += 1usize
        }
        i += 1usize
    }
}

copy type Slots<region r, K, V> {
    items: read [core.mem.MaybeUninit<Bucket<K, V>>] from r
    controls: read [u8] from r
}
extend<region r, K, V> Slots<region r, K, V> {
    fn occupied(index: usize): bool { self.controls[index] < 128u8 }
    fn at(index: usize): read Bucket<K, V> from r {
        unsafe { read *self.items.as_ptr().add(index).cast<Bucket<K, V>>() }
    }
}

// A control below 128 owns exactly one initialized bucket; all other payload slots are uninitialized.
type Table<K, V, A: Allocator> {
    ptr: ptr<mut Bucket<K, V>>
    controls: ptr<mut u8>
    cap: usize
    count: usize
    deleted: usize
    a: A
    drop {
        let payload = unsafe { layout_unchecked(self.cap * core.mem.size_of<Bucket<K, V>>(), core.mem.align_of<Bucket<K, V>>()) }
        let control = unsafe { layout_unchecked(if self.cap == 0usize { 0usize } else { self.cap + 16usize }, 1usize) }
        let _free_controls = unsafe { free_block(self.controls, control, core.ptr.from_mut(self.a)) }
        let _free_payload = unsafe { free_block(self.ptr.cast<u8>(), payload, core.ptr.from_mut(self.a)) }
        if core.mem.needs_drop<Bucket<K, V>>() {
            let n = self.compact()
            unsafe { super.vec.drop_run(self.ptr, n) }
        }
    }
}
const fn table_in<K, V, A: Allocator>(take a: A): Table<K, V, A> {
    Table(dangling_for<Bucket<K, V>>(), dangling_for<u8>(), 0usize, 0usize, 0usize, take a)
}
extend<K, V, A: Allocator> Table<K, V, A> {
    fn occupied(index: usize): bool {
        index < self.cap && unsafe { *self.controls.add(index) < 128u8 }
    }
    fn len(): usize { self.count }
    fn is_empty(): bool { self.count == 0usize }
    fn allocator(): read A from self { read self.a }
    fn as_ptr(): ptr<read Bucket<K, V>> { self.ptr.cast_const() }
    mut fn as_mut_ptr(): ptr<mut Bucket<K, V>> { self.ptr }
    fn get(index: usize): (read Bucket<K, V> from self)? {
        if self.occupied(index) { present(unsafe { read *self.ptr.add(index) }) } else { none }
    }
    fn view(): Slots<region self, K, V> {
        Slots(
            unsafe { core.slice.from_raw_parts(self.ptr.cast<core.mem.MaybeUninit<Bucket<K, V>>>().cast_const(), self.cap) },
            unsafe { core.slice.from_raw_parts(self.controls.cast_const(), self.cap) }
        )
    }
    fn iter(): Iter<region self, K, V> {
        Iter(present(self.view()), 0usize, self.cap, self.count)
    }
    // Compaction is only for destruction/drain: controls are empty before any user destructor runs.
    mut fn compact(): usize {
        let n = self.count
        self.count = 0usize
        self.deleted = 0usize
        var output = 0usize
        var index = 0usize
        while index < self.cap {
            if self.occupied(index) {
                if output != index {
                    unsafe { core.ptr.write(self.ptr.add(output), core.ptr.`read`(self.ptr.add(index))) }
                }
                output += 1usize
            }
            set_control(self.controls, self.cap, index, 128u8)
            index += 1usize
        }
        n
    }
    mut fn clear(): Unit {
        if core.mem.needs_drop<Bucket<K, V>>() {
            let n = self.compact()
            unsafe { super.vec.drop_run(self.ptr, n) }
        } else {
            self.count = 0usize
            self.deleted = 0usize
            if self.cap != 0usize {
                unsafe { core.ptr.write_bytes(self.controls, 128u8, self.cap + 16usize) }
            }
        }
    }
    mut fn remove(index: usize): Bucket<K, V> {
        set_control(self.controls, self.cap, index, 254u8)
        self.count -= 1usize
        self.deleted += 1usize
        unsafe { core.ptr.`read`(self.ptr.add(index)) }
    }
}
extend<K, V, A: Allocator> Table<K, V, A> implements core.ops.Index<usize> {
    type Output = Bucket<K, V>
    fn index(read index: usize): read Bucket<K, V> from self {
        match self.get(index) {
            present(entry) => entry,
            none => super.alloc.panic_precondition()
        }
    }
}

pub type DefaultHasher { hasher: SipHasher }
extend DefaultHasher {
    pub static fn new(): DefaultHasher { DefaultHasher(sip13(0u64, 0u64)) }
}
extend DefaultHasher implements Clone {
    fn clone(): DefaultHasher { DefaultHasher(self.hasher.clone()) }
}
extend DefaultHasher implements Default {
    static fn default(): DefaultHasher { DefaultHasher.new() }
}
extend DefaultHasher implements Hasher {
    mut fn write(read bytes: [u8]): Unit { self.hasher.write(bytes) }
    fn finish(): u64 { self.hasher.finish() }
}

pub copy type DefaultHashBuilder {}
extend DefaultHashBuilder implements Clone {
    fn clone(): DefaultHashBuilder { DefaultHashBuilder() }
}
extend DefaultHashBuilder implements BuildHasher {
    type Hasher = SipHasher
    fn build_hasher(): SipHasher { sip13(0u64, 0u64) }
}
extend DefaultHashBuilder implements Default {
    static fn default(): DefaultHashBuilder { DefaultHashBuilder() }
}
extend DefaultHashBuilder implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("DefaultHashBuilder")
    }
}
extend DefaultHasher implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("DefaultHasher")
        try debug.finish_non_exhaustive()
    }
}

pub type Map<K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    entries: Table<K, V, A>
    builder: S
}

pub type MapDrain<region r, K, V, A: Allocator> {
    inner: mut Table<K, V, A> from r
    front: usize
    back: usize
    drop {
        let n = self.back - self.front
        let pointer = unsafe { self.inner.ptr.add(self.front) }
        self.front = self.back
        unsafe { super.vec.drop_run(pointer, n) }
    }
}
extend<region r, K, V, A: Allocator> MapDrain<region r, K, V, A> {
    fn as_slice(): read [Bucket<K, V>] from self {
        unsafe { read *super.vec.slice_ptr(self.inner.ptr.add(self.front), self.back - self.front) }
    }
}
extend<region r, K, V, A: Allocator> MapDrain<region r, K, V, A> implements Iterator {
    type Item = (K, V)
    mut fn next(): (K, V)? {
        if self.front == self.back { return none }
        let index = self.front
        self.front += 1usize
        let entry = unsafe { core.ptr.`read`(self.inner.ptr.add(index)) }
        present((entry.key, entry.value))
    }
    fn size_hint(): (usize, usize?) {
        let n = self.back - self.front
        (n, present(n))
    }
}
extend<region r, K, V, A: Allocator> MapDrain<region r, K, V, A> implements BidirectionalIterator {
    mut fn next_back(): (K, V)? {
        if self.front == self.back { return none }
        self.back -= 1usize
        let entry = unsafe { core.ptr.`read`(self.inner.ptr.add(self.back)) }
        present((entry.key, entry.value))
    }
}
extend<region r, K, V, A: Allocator> MapDrain<region r, K, V, A> implements ExactSizeIterator {}
extend<region r, K: fmt.Debug, V: fmt.Debug, A: Allocator> MapDrain<region r, K, V, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let entries = self.as_slice()
        try f.write_str("MapDrain(")
        try f.debug_open("{")
        var i = 0usize
        while i < entries.len() {
            let entry = read entries[i]
            try f.debug_item_start(i == 0usize)
            try K.(fmt.Debug).fmt(entry.key, mut f)
            try f.write_str(": ")
            try V.(fmt.Debug).fmt(entry.value, mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("}", entries.len() == 0usize)
        try f.write_str(")")
    }
}

pub type ExtractIf<region r, K, V, A: Allocator, S: BuildHasher, F> {
    map: mut Map<K, V, A, S> from r
    predicate: F
    index: usize
}
extend<region r, K, V, A: Allocator, S: BuildHasher, F> ExtractIf<region r, K, V, A, S, F> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("ExtractIf")
        try debug.field("index", self.index)
        try debug.finish_non_exhaustive()
    }
}
extend<region r, K: Hash + PartialEq, V, A: Allocator, S: BuildHasher, F: mut fn(read K, mut V): bool> ExtractIf<region r, K, V, A, S, F> implements Iterator {
    type Item = (K, V)
    mut fn next(): (K, V)? {
        while self.index < self.map.entries.cap {
            let index = self.index
            self.index += 1usize
            if !self.map.entries.occupied(index) { continue }
            let entry = unsafe { self.map.entries.as_mut_ptr().add(index) }
            let matches = self.predicate(unsafe { read (*entry).key }, unsafe { mut (*entry).value })
            if matches {
                return present(self.map.remove_index(index))
            }
        }
        none
    }
}

pub fn new_in<K, V, A: Allocator>(take a: A): Map<K, V, A> {
    Map<K, V, A>(allocator: take a)
}
pub fn new<K, V>(): Map<K, V> { new_in(Global()) }
pub fn with_capacity_in<K: Hash + PartialEq, V, A: Allocator>(capacity: usize, take a: A): Map<K, V, A> {
    var map = new_in<K, V, A>(take a)
    map.reserve(capacity)
    map
}
pub fn with_capacity<K: Hash + PartialEq, V>(capacity: usize): Map<K, V> {
    with_capacity_in(capacity, Global())
}
pub const fn with_hasher<K, V, S: BuildHasher>(take builder: S): Map<K, V, Global, S> {
    let result: Map<K, V, Global, S>
    result.entries = table_in<K, V, Global>(Global())
    result.builder = take builder
    result
}
pub fn with_capacity_and_hasher_in<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher>(
    capacity: usize,
    take allocator: A,
    take builder: S
): Map<K, V, A, S> {
    var map = Map<K, V, A, S>(allocator: take allocator, builder: take builder)
    map.reserve(capacity)
    map
}
pub fn with_capacity_and_hasher<K: Hash + PartialEq, V, S: BuildHasher>(
    capacity: usize,
    take builder: S
): Map<K, V, Global, S> {
    with_capacity_and_hasher_in(capacity, Global(), take builder)
}

extend<K, V> Map<K, V> {
    pub init() {
        self.entries = table_in<K, V, Global>(Global())
        self.builder = DefaultHashBuilder()
    }
}

extend<K, V, A: Allocator> Map<K, V, A> {
    pub init(take allocator: A) {
        self.entries = table_in<K, V, A>(take allocator)
        self.builder = DefaultHashBuilder()
    }
}

extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub init(take allocator: A, take builder: S) {
        self.entries = table_in<K, V, A>(take allocator)
        self.builder = take builder
    }
}

extend<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub fn len(): usize { self.entries.len() }
    pub fn is_empty(): bool { self.entries.is_empty() }
    pub fn capacity(): usize {
        table_limit(self.entries.cap) - self.entries.deleted
    }
    pub fn allocator(): read A from self { self.entries.allocator() }

    @cfg(target_arch = "x86_64")
    @inline(always)
    fn find_pos<Q: PartialEq + unsized>(hash: u64, read key: Q): (usize, usize?) where K: KeyView<Q> {
        if self.entries.cap == 0usize { return (0usize, none) }
        let mask = self.entries.cap - 1usize
        let tag = (hash >> 57u64) as u128
        let needle = tag * 0x01010101010101010101010101010101u128
        var start = (hash as usize) & mask
        var step = 0usize
        var available = usize.MAX
        while true {
            // Sixteen initialized mirrors make every group load valid, including capacity eight.
            let lanes = unsafe { self.entries.controls.add(start).cast<u128>().read_unaligned() }
            var matching = lanes
            var matches = 0u32
            unsafe {
                asm!("pcmpeqb {matching:x}, {needle:x}",
                     "pmovmskb {matches:e}, {matching:x}",
                     matching = inout(xmm_reg) matching, needle = in(xmm_reg) needle,
                     matches = lateout(reg) matches, options(pure,nomem,nostack,preserves_flags))
            }
            while matches != 0u32 {
                let index = (start + matches.trailing_zeros() as usize) & mask
                let entry = unsafe { read *self.entries.as_ptr().add(index) }
                if Q.(PartialEq<Q>).eq(K.(KeyView<Q>).key_view(entry.key), key) {
                    return (index, present(index))
                }
                matches = matches & matches.wrapping_sub(1u32)
            }
            var empty = 0x80808080808080808080808080808080u128
            var space = 0u32
            var vacant = 0u32
            unsafe {
                asm!("pmovmskb {space:e}, {lanes:x}",
                     "pcmpeqb {empty:x}, {lanes:x}",
                     "pmovmskb {vacant:e}, {empty:x}",
                     lanes = in(xmm_reg) lanes, empty = inout(xmm_reg) empty,
                     space = lateout(reg) space, vacant = lateout(reg) vacant,
                     options(pure,nomem,nostack,preserves_flags))
            }
            if available == usize.MAX && space != 0u32 {
                available = (start + space.trailing_zeros() as usize) & mask
            }
            if vacant != 0u32 { return (available, none) }
            step += 16usize
            start = (start + step) & mask
        }
        (0usize, none)
    }

    @cfg(not(target_arch = "x86_64"))
    @inline(always)
    fn find_pos<Q: PartialEq + unsized>(hash: u64, read key: Q): (usize, usize?) where K: KeyView<Q> {
        if self.entries.cap == 0usize { return (0usize, none) }
        let mask = self.entries.cap - 1usize
        let tag = (hash >> 57u64) as u8
        var start = (hash as usize) & mask
        var step = 0usize
        var available = usize.MAX
        while true {
            var lane = 0usize
            var vacant = false
            while lane < 16usize {
                let index = (start + lane) & mask
                let control = unsafe { *self.entries.controls.add(index) }
                if control == tag {
                    let entry = unsafe { read *self.entries.as_ptr().add(index) }
                    if Q.(PartialEq<Q>).eq(K.(KeyView<Q>).key_view(entry.key), key) {
                        return (index, present(index))
                    }
                } else if control >= 128u8 {
                    if available == usize.MAX { available = index }
                    if control == 128u8 { vacant = true }
                }
                lane += 1usize
            }
            if vacant { return (available, none) }
            step += 16usize
            start = (start + step) & mask
        }
        (0usize, none)
    }
    @inline(always)
    fn find_entry<Q: Hash + PartialEq + unsized>(read key: Q): usize? where K: KeyView<Q> {
        let hash = self.builder.hash_one(key)
        self.find_pos(hash, key).1
    }

    @inline(never)
    mut fn rebuild(ncap: usize): Unit throws TryReserveError {
        let (payload, control, hashes) = try rebuild_layouts(layout_of<Bucket<K, V>>(), ncap, self.entries.count)
        let a = core.ptr.from_mut(self.entries.a)
        let np = (try allocate_rebuild_block(self.entries.a, payload, dangling_for<Bucket<K, V>>().cast<u8>())).cast<Bucket<K, V>>()
        let payload_guard = unsafe { free_block(np.cast<u8>(), payload, a) }
        let nc = try allocate_rebuild_block(self.entries.a, control, dangling_for<u8>())
        let control_guard = unsafe { free_block(nc, control, a) }
        let nh = (try allocate_rebuild_block(self.entries.a, hashes, dangling_for<u64>().cast<u8>())).cast<u64>()
        let _hash_guard = unsafe { free_block(nh.cast<u8>(), hashes, a) }
        if control.size() != 0usize {
            unsafe { core.ptr.write_bytes(nc, 128u8, control.size()) }
        }
        let old_cap = self.entries.cap
        let old_ptr = self.entries.ptr
        let old_controls = self.entries.controls
        // Finish every fallible allocation and hash callback before moving any owned payload.
        var ordinal = 0usize
        var i = 0usize
        while i < old_cap {
            if unsafe { *old_controls.add(i) < 128u8 } {
                let hash = self.builder.hash_one(unsafe { read (*old_ptr.add(i)).key })
                unsafe { core.ptr.write(nh.add(ordinal), hash) }
                ordinal += 1usize
            }
            i += 1usize
        }
        let bucket_size = core.mem.size_of<Bucket<K, V>>()
        unsafe {
            move_rebuild_entries(old_ptr.cast<u8>().cast_const(), old_controls.cast_const(), old_cap,
                np.cast<u8>(), nc, ncap, nh.cast_const(), bucket_size)
        }
        let old_payload = unsafe { layout_unchecked(old_cap * bucket_size, core.mem.align_of<Bucket<K, V>>()) }
        let old_control = unsafe { layout_unchecked(if old_cap == 0usize { 0usize } else { old_cap + 16usize }, 1usize) }
        let _free_controls = unsafe { free_block(old_controls, old_control, a) }
        let _free_payload = unsafe { free_block(old_ptr.cast<u8>(), old_payload, a) }
        self.entries.ptr = np
        self.entries.controls = nc
        self.entries.cap = ncap
        self.entries.deleted = 0usize
        core.mem.forget(take control_guard)
        core.mem.forget(take payload_guard)
    }

    @inline(never)
    mut fn try_reserve_impl(extra: usize): Unit throws TryReserveError {
        let need = match (self.entries.len()).checked_add(extra) {
            present(n) => n,
            none => throw TryReserveError.capacity_overflow()
        }
        if need <= self.capacity() { return () }
        var ncap = if self.entries.cap == 0usize { 8usize } else { self.entries.cap }
        while need > table_limit(ncap) {
            if ncap > isize.MAX as usize / 2usize {
                throw TryReserveError.capacity_overflow()
            }
            ncap *= 2usize
        }
        try self.rebuild(ncap)
    }
    pub mut fn try_reserve(extra: usize): Unit throws TryReserveError {
        try self.try_reserve_impl(extra)
    }
    pub mut fn try_reserve_exact(extra: usize): Unit throws TryReserveError {
        try self.try_reserve_impl(extra)
    }
    pub mut fn reserve(extra: usize): Unit {
        match capture self.try_reserve(extra) {
            success(_) => (),
            failure(error) => error.handle()
        }
    }
    pub mut fn reserve_exact(extra: usize): Unit {
        match capture self.try_reserve_exact(extra) {
            success(_) => (),
            failure(error) => error.handle()
        }
    }
    pub mut fn shrink_to_fit(): Unit {
        var target = 0usize
        if self.entries.len() != 0usize {
            target = 8usize
            while self.entries.len() > table_limit(target) {
                target *= 2usize
            }
        }
        if target < self.entries.cap {
            match capture self.rebuild(target) {
                success(_) => (),
                failure(_) => ()
            }
        }
    }
    pub mut fn shrink_to(min_capacity: usize): Unit {
        let old_capacity = self.capacity()
        if old_capacity <= min_capacity { return () }
        let wanted = if min_capacity > self.entries.len() { min_capacity } else { self.entries.len() }
        var target = 0usize
        if wanted != 0usize {
            target = 8usize
            while wanted > table_limit(target) {
                if target > isize.MAX as usize / 2usize { return () }
                target *= 2usize
            }
        }
        if target < self.entries.cap {
            match capture self.rebuild(target) {
                success(_) => (),
                failure(_) => ()
            }
        }
    }

    // Lookups take a borrowed query `Q` that the stored key views as (a
    // `String` key is searched with a `Text`); equal keys and queries must hash
    // alike (see `KeyView`).
    pub fn contains_key<Q: Hash + PartialEq + unsized>(read key: Q): bool where K: KeyView<Q> {
        match self.find_entry(key) { present(_) => true, none => false }
    }
    @inline(always)
    pub fn get<Q: Hash + PartialEq + unsized>(read key: Q): (read V from self)? where K: KeyView<Q> {
        match self.find_entry(key) {
            present(s) => present(unsafe { read (*self.entries.as_ptr().add(s)).value }),
            none => none
        }
    }
    pub fn get_key_value<Q: Hash + PartialEq + unsized>(read key: Q): (read K from self, read V from self)? where K: KeyView<Q> {
        match self.find_entry(key) {
            present(s) => {
                let entry = unsafe { read *self.entries.as_ptr().add(s) }
                present((read entry.key, read entry.value))
            },
            none => none
        }
    }
    pub mut fn get_mut<Q: Hash + PartialEq + unsized>(read key: Q): (mut V from self)? where K: KeyView<Q> {
        match self.find_entry(key) {
            present(s) => present(unsafe { mut (*self.entries.as_mut_ptr().add(s)).value }),
            none => none
        }
    }
    pub mut fn get_disjoint_mut<Q: Hash + PartialEq + unsized, R: Hash + PartialEq + unsized>(
        read first: Q,
        read second: R
    ): (mut V from self, mut V from self)? where K: KeyView<Q> + KeyView<R> {
        let first_index = self.find_entry(first)
        let second_index = self.find_entry(second)
        match first_index {
            present(i) => match second_index {
                present(j) => {
                    if i == j { super.alloc.panic_precondition() }
                    let entries = self.entries.as_mut_ptr()
                    present((
                        unsafe { mut (*entries.add(i)).value },
                        unsafe { mut (*entries.add(j)).value }
                    ))
                },
                none => none
            },
            none => none
        }
    }
    // Safety: both keys must exist and designate distinct entries.
    pub mut unsafe fn get_disjoint_unchecked_mut<Q: Hash + PartialEq + unsized, R: Hash + PartialEq + unsized>(
        read first: Q,
        read second: R
    ): (mut V from self, mut V from self) where K: KeyView<Q> + KeyView<R> {
        let i = match self.find_entry(first) {
            present(index) => index,
            none => core.panic.unreachable()
        }
        let j = match self.find_entry(second) {
            present(index) => index,
            none => core.panic.unreachable()
        }
        if i == j { core.panic.unreachable() }
        let entries = self.entries.as_mut_ptr()
        (mut (*entries.add(i)).value, mut (*entries.add(j)).value)
    }
    pub mut fn extract_if<F: mut fn(read K, mut V): bool>(
        take predicate: F
    ): ExtractIf<region self, K, V, A, S, F> {
        ExtractIf(mut self, predicate, 0usize)
    }
    pub mut fn retain<F: mut fn(read K, mut V): bool>(take predicate: F): Unit {
        var keep = predicate
        var index = 0usize
        while index < self.entries.cap {
            let current = index
            index += 1usize
            if !self.entries.occupied(current) { continue }
            let entry = unsafe { self.entries.as_mut_ptr().add(current) }
            if !keep(unsafe { read (*entry).key }, unsafe { mut (*entry).value }) {
                let _removed = self.remove_index(current)
            }
        }
    }

    // Inserts or replaces; a replaced value is returned. On allocation failure
    // the map is unchanged and the pair is dropped.
    pub mut fn try_insert(take key: K, take value: V): V? throws TryReserveError {
        let hash = self.builder.hash_one(key)
        let found = self.find_pos(hash, key)
        match found.1 {
            present(s) => {
                let slot = unsafe { core.ptr.from_mut((*self.entries.as_mut_ptr().add(s)).value) }
                return present(unsafe { core.ptr.replace(slot, value) })
            },
            none => {}
        }
        let _ = try self.try_append(hash, key, value, found.0)
        none
    }

    @inline(never)
    mut fn try_append(hash: u64, take key: K, take value: V, vacant: usize): usize throws TryReserveError {
        var pos = vacant
        let reuses_deleted = self.entries.cap != 0usize &&
            unsafe { *self.entries.controls.add(pos) == 254u8 }
        if reuses_deleted {
            self.entries.deleted -= 1usize
        } else if self.entries.count >= self.capacity() {
            try self.try_reserve(1usize)
            pos = vacant_slot(self.entries.controls, self.entries.cap, hash)
        }
        unsafe { core.ptr.write(self.entries.ptr.add(pos), Bucket(key, value)) }
        set_control(self.entries.controls, self.entries.cap, pos, (hash >> 57u64) as u8)
        self.entries.count += 1usize
        pos
    }
    pub mut fn insert(take key: K, take value: V): V? {
        let outcome = capture self.try_insert(key, value)
        match take outcome {
            success(old) => old,
            failure(error) => error.handle()
        }
    }

    // Returns the value for `key`, inserting `value` first when absent.
    pub mut fn or_insert(take key: K, take value: V): mut V from self {
        let hash = self.builder.hash_one(key)
        let found = self.find_pos(hash, key)
        let s = match found.1 {
            present(index) => index,
            none => {
                match capture self.try_append(hash, key, value, found.0) {
                    success(index) => index,
                    failure(error) => error.handle()
                }
            }
        }
        unsafe { mut (*self.entries.as_mut_ptr().add(s)).value }
    }

    mut fn remove_index(s: usize): (K, V) {
        let entry = self.entries.remove(s)
        (entry.key, entry.value)
    }
    pub mut fn remove_entry<Q: Hash + PartialEq + unsized>(read key: Q): (K, V)? where K: KeyView<Q> {
        let hash = self.builder.hash_one(key)
        let found = self.find_pos(hash, key)
        match found.1 {
            present(index) => present(self.remove_index(index)),
            none => none
        }
    }
    pub mut fn remove<Q: Hash + PartialEq + unsized>(read key: Q): V? where K: KeyView<Q> {
        match take self.remove_entry(key) {
            present(entry) => present(entry.1),
            none => none
        }
    }

    pub mut fn clear(): Unit {
        self.entries.clear()
    }

    pub mut fn drain(): MapDrain<region self, K, V, A> {
        let count = self.entries.compact()
        MapDrain(mut self.entries, 0usize, count)
    }
}

extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub fn hasher(): read S from self { read self.builder }
}
extend<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher, Q: Hash + PartialEq + unsized> Map<K, V, A, S> implements core.ops.Index<Q> where K: KeyView<Q> {
    type Output = V
    fn index(read key: Q): read V from self {
        match self.get(key) {
            present(value) => value,
            none => super.alloc.panic_precondition()
        }
    }
}

// Set of keys backed by a map with unit values.
pub type Set<K, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> { map: Map<K, Unit, A, S> }

const fn set_from_map<K, A: Allocator, S: BuildHasher>(take map: Map<K, Unit, A, S>): Set<K, A, S> {
    let result: Set<K, A, S>
    result.map = take map
    result
}

pub fn set_new_in<K, A: Allocator>(take a: A): Set<K, A> {
    Set<K, A>(allocator: take a)
}
pub fn set_new<K>(): Set<K> { Set<K>() }
pub fn set_with_capacity_in<K: Hash + PartialEq, A: Allocator>(capacity: usize, take a: A): Set<K, A> {
    var set = set_new_in<K, A>(take a)
    set.reserve(capacity)
    set
}
pub fn set_with_capacity<K: Hash + PartialEq>(capacity: usize): Set<K> {
    set_with_capacity_in(capacity, Global())
}
pub const fn set_with_hasher<K, S: BuildHasher>(take builder: S): Set<K, Global, S> {
    set_from_map(with_hasher<K, Unit, S>(take builder))
}
pub fn set_with_capacity_and_hasher_in<K: Hash + PartialEq, A: Allocator, S: BuildHasher>(
    capacity: usize,
    take allocator: A,
    take builder: S
): Set<K, A, S> {
    set_from_map(with_capacity_and_hasher_in<K, Unit, A, S>(capacity, take allocator, take builder))
}
pub fn set_with_capacity_and_hasher<K: Hash + PartialEq, S: BuildHasher>(
    capacity: usize,
    take builder: S
): Set<K, Global, S> {
    set_with_capacity_and_hasher_in(capacity, Global(), take builder)
}

extend<K> Set<K> {
    pub init() { self.map = new<K, Unit>() }
}

extend<K, A: Allocator> Set<K, A> {
    pub init(take allocator: A) {
        self.map = new_in<K, Unit, A>(take allocator)
    }
}

extend<K, A: Allocator, S: BuildHasher> Set<K, A, S> {
    pub init(take allocator: A, take builder: S) {
        self.map = Map<K, Unit, A, S>(allocator: take allocator, builder: take builder)
    }
}

extend<K: Hash + PartialEq, A: Allocator, S: BuildHasher> Set<K, A, S> {
    pub fn len(): usize { self.map.len() }
    pub fn capacity(): usize { self.map.capacity() }
    pub fn is_empty(): bool { self.map.is_empty() }
    pub mut fn try_reserve(extra: usize): Unit throws TryReserveError {
        try self.map.try_reserve(extra)
    }
    pub mut fn try_reserve_exact(extra: usize): Unit throws TryReserveError {
        try self.map.try_reserve_exact(extra)
    }
    pub mut fn reserve(extra: usize): Unit { self.map.reserve(extra) }
    pub mut fn reserve_exact(extra: usize): Unit { self.map.reserve_exact(extra) }
    pub mut fn shrink_to_fit(): Unit { self.map.shrink_to_fit() }
    pub mut fn shrink_to(min_capacity: usize): Unit { self.map.shrink_to(min_capacity) }
    pub fn contains<Q: Hash + PartialEq + unsized>(read key: Q): bool where K: KeyView<Q> { self.map.contains_key(key) }
    pub fn get<Q: Hash + PartialEq + unsized>(read key: Q): (read K from self)? where K: KeyView<Q> {
        match self.map.find_entry(key) {
            present(index) => match self.map.entries.get(index) {
                present(entry) => present(read entry.key),
                none => none
            },
            none => none
        }
    }
    // True when the key was newly added.
    pub mut fn insert(take key: K): bool {
        match self.map.insert(key, ()) { present(_) => false, none => true }
    }
    pub mut fn try_insert(take key: K): bool throws TryReserveError {
        match try self.map.try_insert(key, ()) { present(_) => false, none => true }
    }
    pub mut fn remove<Q: Hash + PartialEq + unsized>(read key: Q): bool where K: KeyView<Q> {
        match self.map.remove(key) { present(_) => true, none => false }
    }
    pub mut fn `take`<Q: Hash + PartialEq + unsized>(read key: Q): K? where K: KeyView<Q> {
        match take self.map.remove_entry(key) {
            present(entry) => present(entry.0),
            none => none
        }
    }
    pub mut fn replace(take value: K): K? {
        let hash = self.map.builder.hash_one(value)
        let found = self.map.find_pos(hash, value)
        match found.1 {
            present(index) => {
                let entries = self.map.entries.as_mut_ptr()
                // The exclusive receiver keeps this live entry stable; equal
                // keys preserve the hash and probing position.
                let key_slot = unsafe { core.ptr.from_mut((*entries.add(index)).key) }
                present(unsafe { core.ptr.replace(key_slot, value) })
            },
            none => {
                let _index = match capture self.map.try_append(hash, value, (), found.0) {
                    success(index) => index,
                    failure(error) => error.handle()
                }
                none
            }
        }
    }
    pub mut fn clear(): Unit { self.map.clear() }
}

extend<K, A: Allocator, S: BuildHasher> Set<K, A, S> {
    pub fn hasher(): read S from self { self.map.hasher() }
}

pub type SetDrain<region r, K, A: Allocator> {
    inner: MapDrain<region r, K, Unit, A>
}
extend<region r, K, A: Allocator> SetDrain<region r, K, A> implements Iterator {
    type Item = K
    mut fn next(): K? {
        match take self.inner.next() {
            present(entry) => present(entry.0),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<region r, K, A: Allocator> SetDrain<region r, K, A> implements BidirectionalIterator {
    mut fn next_back(): K? {
        match take self.inner.next_back() {
            present(entry) => present(entry.0),
            none => none
        }
    }
}
extend<region r, K, A: Allocator> SetDrain<region r, K, A> implements ExactSizeIterator {}
extend<region r, K: fmt.Debug, A: Allocator> SetDrain<region r, K, A> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let entries = self.inner.as_slice()
        try f.write_str("SetDrain(")
        try f.debug_open("{")
        var i = 0usize
        while i < entries.len() {
            try f.debug_item_start(i == 0usize)
            try K.(fmt.Debug).fmt(entries[i].key, mut f)
            try f.debug_item_end()
            i += 1usize
        }
        try f.debug_close("}", entries.len() == 0usize)
        try f.write_str(")")
    }
}

pub type SetExtractIf<region r, K, A: Allocator, S: BuildHasher, F> {
    set: mut Set<K, A, S> from r
    predicate: F
    index: usize
}
extend<region r, K: Hash + PartialEq, A: Allocator, S: BuildHasher, F: mut fn(read K): bool> SetExtractIf<region r, K, A, S, F> implements Iterator {
    type Item = K
    mut fn next(): K? {
        while self.index < self.set.map.entries.cap {
            let index = self.index
            self.index += 1usize
            if !self.set.map.entries.occupied(index) { continue }
            let entry = unsafe { self.set.map.entries.as_mut_ptr().add(index) }
            if self.predicate(unsafe { read (*entry).key }) {
                return present(self.set.map.remove_index(index).0)
            }
        }
        none
    }
}

// Each algebra iterator scans the left set first, then the right set when its
// operation needs right-only elements. Set iteration order remains unspecified.
pub type SetAlgebra<region r, K, A: Allocator, S: BuildHasher> {
    left: read Set<K, A, S> from r
    right: read Set<K, A, S> from r
    mode: u8
    side: u8
    index: usize
}
extend<region r, K, A: Allocator, S: BuildHasher> SetAlgebra<region r, K, A, S> implements Clone {
    fn clone(): SetAlgebra<region r, K, A, S> {
        SetAlgebra(self.left, self.right, self.mode, self.side, self.index)
    }
}
extend<region r, K: Hash + PartialEq, A: Allocator, S: BuildHasher> SetAlgebra<region r, K, A, S> implements Iterator {
    type Item = read K from r
    mut fn next(): (read K from r)? {
        while self.side < 2u8 {
            if (self.mode == 1u8 || self.mode == 2u8) && self.side == 1u8 { return none }
            if self.side == 0u8 {
                if self.index >= self.left.map.entries.cap {
                    self.side = 1u8
                    self.index = 0usize
                    continue
                }
                let i = self.index
                self.index += 1usize
                if !self.left.map.entries.occupied(i) { continue }
                let key = read self.left.map.entries[i].key
                if self.mode == 0u8 { return present(key) }
                let in_right = match self.right.map.find_entry(key) {
                    present(_) => true,
                    none => false
                }
                let include = match self.mode {
                    1u8 => in_right,
                    2u8 => !in_right,
                    _ => !in_right
                }
                if include { return present(read self.left.map.entries[i].key) }
            } else {
                if self.index >= self.right.map.entries.cap { return none }
                let i = self.index
                self.index += 1usize
                if !self.right.map.entries.occupied(i) { continue }
                let key = read self.right.map.entries[i].key
                let in_left = match self.left.map.find_entry(key) {
                    present(_) => true,
                    none => false
                }
                if (self.mode == 0u8 || self.mode == 3u8) && !in_left {
                    return present(read self.right.map.entries[i].key)
                }
            }
        }
        none
    }
}

extend<region r, K: Hash + PartialEq + fmt.Debug, A: Allocator, S: BuildHasher> SetAlgebra<region r, K, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        let name = match self.mode {
            0u8 => "Union",
            1u8 => "Intersection",
            2u8 => "Difference",
            _ => "SymmetricDifference"
        }
        var debug = try f.debug_struct(name)
        try debug.field("left", read self.left)
        try debug.field("right", read self.right)
        try debug.field("side", self.side)
        try debug.field("index", self.index)
        try debug.finish()
    }
}

extend<K: Hash + PartialEq, A: Allocator, S: BuildHasher> Set<K, A, S> {
    pub fn `union`(read other: Set<K, A, S> from self): SetAlgebra<region self, K, A, S> {
        SetAlgebra(read self, read other, 0u8, 0u8, 0usize)
    }
    pub fn intersection(read other: Set<K, A, S> from self): SetAlgebra<region self, K, A, S> {
        SetAlgebra(read self, read other, 1u8, 0u8, 0usize)
    }
    pub fn difference(read other: Set<K, A, S> from self): SetAlgebra<region self, K, A, S> {
        SetAlgebra(read self, read other, 2u8, 0u8, 0usize)
    }
    pub fn symmetric_difference(read other: Set<K, A, S> from self): SetAlgebra<region self, K, A, S> {
        SetAlgebra(read self, read other, 3u8, 0u8, 0usize)
    }
    pub fn is_subset(read other: Set<K, A, S>): bool {
        var i = 0usize
        while i < self.map.entries.cap {
            if !self.map.entries.occupied(i) { i += 1usize; continue }
            if !other.contains(self.map.entries[i].key) { return false }
            i += 1usize
        }
        true
    }
    pub fn is_superset(read other: Set<K, A, S>): bool {
        var i = 0usize
        while i < other.map.entries.cap {
            if !other.map.entries.occupied(i) { i += 1usize; continue }
            if !self.contains(other.map.entries[i].key) { return false }
            i += 1usize
        }
        true
    }
    pub fn is_disjoint(read other: Set<K, A, S>): bool {
        var i = 0usize
        while i < self.map.entries.cap {
            if !self.map.entries.occupied(i) { i += 1usize; continue }
            if other.contains(self.map.entries[i].key) { return false }
            i += 1usize
        }
        true
    }
    pub mut fn drain(): SetDrain<region self, K, A> { SetDrain(self.map.drain()) }
    pub mut fn extract_if<F: mut fn(read K): bool>(
        take predicate: F
    ): SetExtractIf<region self, K, A, S, F> {
        SetExtractIf(mut self, predicate, 0usize)
    }
    pub mut fn retain<F: mut fn(read K): bool>(take predicate: F): Unit {
        var keep = predicate
        var index = 0usize
        while index < self.map.entries.cap {
            let current = index
            index += 1usize
            if !self.map.entries.occupied(current) { continue }
            let entry = unsafe { self.map.entries.as_mut_ptr().add(current) }
            if !keep(unsafe { read (*entry).key }) {
                let _removed = self.map.remove_index(current)
            }
        }
    }
}


// Borrowed cursors scan only initialized buckets and never expose mutable keys.
pub type Iter<region r, K, V> {
    items: Slots<region r, K, V>?
    front: usize
    back: usize
    remaining: usize
}
extend<region r, K, V> Iter<region r, K, V> implements Iterator {
    type Item = read Bucket<K, V> from r
    mut fn next(): (read Bucket<K, V> from r)? {
        match read self.items {
            present(items) => {
                while self.front < self.back {
                    let index = self.front
                    self.front += 1usize
                    if items.occupied(index) {
                        self.remaining -= 1usize
                        return present(items.at(index))
                    }
                }
                none
            },
            none => none
        }
    }
    fn size_hint(): (usize, usize?) {
        (self.remaining, present(self.remaining))
    }
}
extend<region r, K, V> Iter<region r, K, V> implements Clone {
    fn clone(): Iter<region r, K, V> { Iter(self.items, self.front, self.back, self.remaining) }
}
extend<region r, K, V> Iter<region r, K, V> implements ExactSizeIterator {}
extend<region r, K, V> Iter<region r, K, V> implements Default {
    static fn default(): Iter<region r, K, V> { Iter(none, 0usize, 0usize, 0usize) }
}
extend<region r, K: fmt.Debug, V: fmt.Debug> Iter<region r, K, V> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Iter(")
        try f.debug_open("[")
        var first = true
        for entry in self.clone() {
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(entry.key, mut f)
            try f.write_str(": ")
            try V.(fmt.Debug).fmt(entry.value, mut f)
            try f.debug_item_end()
            first = false
        }
        try f.debug_close("]", first)
        try f.write_str(")")
    }
}
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements Iterable {
    type Item = Bucket<K, V>
    type Iter<region r> = Iter<region r, K, V>
    fn iter<region r>(receiver read self: Self from r): Iter<region r, K, V> {
        self.entries.iter()
    }
}
extend<K, A: Allocator, S: BuildHasher> Set<K, A, S> implements Iterable {
    type Item = K
    type Iter<region r> = Keys<region r, K, Unit>
    fn iter<region r>(receiver read self: Self from r): Keys<region r, K, Unit> {
        Keys(self.map.entries.iter())
    }
}

pub type MapIntoIter<K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    map: Map<K, V, A, S>
    index: usize
}
extend<K, V, A: Allocator, S: BuildHasher> MapIntoIter<K, V, A, S> implements Iterator {
    type Item = (K, V)
    mut fn next(): (K, V)? {
        while self.index != 0usize {
            self.index -= 1usize
            if self.map.entries.occupied(self.index) {
                let entry = self.map.entries.remove(self.index)
                return present((entry.key, entry.value))
            }
        }
        none
    }
    fn size_hint(): (usize, usize?) {
        let remaining = self.map.entries.len()
        (remaining, present(remaining))
    }
}
extend<K, V, A: Allocator, S: BuildHasher> MapIntoIter<K, V, A, S> implements ExactSizeIterator {}
extend<K: fmt.Debug, V: fmt.Debug, A: Allocator, S: BuildHasher> MapIntoIter<K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("MapIntoIter(")
        try Map<K, V, A, S>.(fmt.Debug).fmt(read self.map, mut f)
        try f.write_str(")")
    }
}
extend<K: Hash + PartialEq, V, A: Allocator + Default, S: BuildHasher + Default> MapIntoIter<K, V, A, S> implements Default {
    static fn default(): MapIntoIter<K, V, A, S> {
        MapIntoIter(Map<K, V, A, S>.(Default).default(), 0usize)
    }
}
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements OwnedIterable {
    type Item = (K, V)
    type IntoIter = MapIntoIter<K, V, A, S>
    fn into_iter(receiver take self: Self): MapIntoIter<K, V, A, S> {
        let back = self.entries.cap
        MapIntoIter(take self, back)
    }
}

extend<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub take fn into_keys(): IntoKeys<K, V, A, S> { IntoKeys(self.into_iter()) }
    pub take fn into_values(): IntoValues<K, V, A, S> { IntoValues(self.into_iter()) }
}
pub type IntoKeys<K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> { inner: MapIntoIter<K, V, A, S> }
extend<K, V, A: Allocator, S: BuildHasher> IntoKeys<K, V, A, S> implements Iterator {
    type Item = K
    mut fn next(): K? {
        match take self.inner.next() {
            present(entry) => present(entry.0),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<K, V, A: Allocator, S: BuildHasher> IntoKeys<K, V, A, S> implements ExactSizeIterator {}
extend<K: fmt.Debug, V, A: Allocator, S: BuildHasher> IntoKeys<K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("IntoKeys(")
        try f.debug_open("[")
        var first = true
        for entry in self.inner.map.entries.iter() {
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(entry.key, mut f)
            try f.debug_item_end()
            first = false
        }
        try f.debug_close("]", first)
        try f.write_str(")")
    }
}
extend<K: Hash + PartialEq, V, A: Allocator + Default, S: BuildHasher + Default> IntoKeys<K, V, A, S> implements Default {
    static fn default(): IntoKeys<K, V, A, S> {
        IntoKeys(MapIntoIter<K, V, A, S>.(Default).default())
    }
}
pub type IntoValues<K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> { inner: MapIntoIter<K, V, A, S> }
extend<K, V, A: Allocator, S: BuildHasher> IntoValues<K, V, A, S> implements Iterator {
    type Item = V
    mut fn next(): V? {
        match take self.inner.next() {
            present(entry) => present(entry.1),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<K, V, A: Allocator, S: BuildHasher> IntoValues<K, V, A, S> implements ExactSizeIterator {}
extend<K, V: fmt.Debug, A: Allocator, S: BuildHasher> IntoValues<K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("IntoValues(")
        try f.debug_open("[")
        var first = true
        for entry in self.inner.map.entries.iter() {
            try f.debug_item_start(first)
            try V.(fmt.Debug).fmt(entry.value, mut f)
            try f.debug_item_end()
            first = false
        }
        try f.debug_close("]", first)
        try f.write_str(")")
    }
}
extend<K: Hash + PartialEq, V, A: Allocator + Default, S: BuildHasher + Default> IntoValues<K, V, A, S> implements Default {
    static fn default(): IntoValues<K, V, A, S> {
        IntoValues(MapIntoIter<K, V, A, S>.(Default).default())
    }
}

pub type SetIntoIter<K, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> { inner: MapIntoIter<K, Unit, A, S> }
extend<K, A: Allocator, S: BuildHasher> SetIntoIter<K, A, S> implements Iterator {
    type Item = K
    mut fn next(): K? {
        match take self.inner.next() {
            present(pair) => present(pair.0),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) { self.inner.size_hint() }
}
extend<K, A: Allocator, S: BuildHasher> SetIntoIter<K, A, S> implements ExactSizeIterator {}
extend<K: fmt.Debug, A: Allocator, S: BuildHasher> SetIntoIter<K, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.debug_open("{")
        var first = true
        for entry in self.inner.map.entries.iter() {
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(entry.key, mut f)
            try f.debug_item_end()
            first = false
        }
        try f.debug_close("}", first)
    }
}
extend<K: Hash + PartialEq, A: Allocator + Default, S: BuildHasher + Default> SetIntoIter<K, A, S> implements Default {
    static fn default(): SetIntoIter<K, A, S> {
        SetIntoIter(MapIntoIter<K, Unit, A, S>.(Default).default())
    }
}
extend<K, A: Allocator, S: BuildHasher> Set<K, A, S> implements OwnedIterable {
    type Item = K
    type IntoIter = SetIntoIter<K, A, S>
    fn into_iter(receiver take self: Self): SetIntoIter<K, A, S> {
        SetIntoIter(self.map.into_iter())
    }
}

// The exclusive loan keeps storage stable; advance before issuing each mutable value.
pub type IterMut<region r, K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    map: (mut Map<K, V, A, S> from r)?
    index: usize
    remaining: usize
}
extend<region r, K, V, A: Allocator, S: BuildHasher> IterMut<region r, K, V, A, S> implements Iterator {
    type Item = (read K from r, mut V from r)
    mut fn next(): (read K from r, mut V from r)? {
        match mut self.map {
            present(map) => {
                while self.index < map.entries.cap {
                    let i = self.index
                    self.index += 1usize
                    if !map.entries.occupied(i) { continue }
                    self.remaining -= 1usize
                    let entry = unsafe { map.entries.as_mut_ptr().add(i) }
                    return present((unsafe { read (*entry).key }, unsafe { mut (*entry).value }))
                }
                none
            },
            none => none
        }
    }
    fn size_hint(): (usize, usize?) {
        (self.remaining, present(self.remaining))
    }
}
extend<region r, K, V, A: Allocator, S: BuildHasher> IterMut<region r, K, V, A, S> implements ExactSizeIterator {}
extend<region r, K, V, A: Allocator, S: BuildHasher> IterMut<region r, K, V, A, S> implements Default {
    static fn default(): IterMut<region r, K, V, A, S> { IterMut(none, 0usize, 0usize) }
}
extend<region r, K: fmt.Debug, V: fmt.Debug, A: Allocator, S: BuildHasher> IterMut<region r, K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("IterMut(")
        try f.debug_open("{")
        match read self.map {
            present(map) => {
                var index = self.index
                var first = true
                while index < map.entries.cap {
                    if !map.entries.occupied(index) { index += 1usize; continue }
                    let entry = read map.entries[index]
                    try f.debug_item_start(first)
                    try K.(fmt.Debug).fmt(entry.key, mut f)
                    try f.write_str(": ")
                    try V.(fmt.Debug).fmt(entry.value, mut f)
                    try f.debug_item_end()
                    first = false
                    index += 1usize
                }
            },
            none => {}
        }
        try f.debug_close("}", self.size_hint().0 == 0usize)
        try f.write_str(")")
    }
}
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub mut fn iter_mut(): IterMut<region self, K, V, A, S> {
        let remaining = self.entries.count
        IterMut(present(mut self), 0usize, remaining)
    }
}

// Generic mutable iteration visits values only: mutable keys could break the
// table's hash invariants.
pub type ValuesMut<region r, K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    map: (mut Map<K, V, A, S> from r)?
    index: usize
    back: usize
    remaining: usize
}
extend<region r, K, V, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements Iterator {
    type Item = mut V from r
    mut fn next(): (mut V from r)? {
        match mut self.map {
            present(map) => {
                while self.index < self.back {
                    let i = self.index
                    self.index += 1usize
                    if !map.entries.occupied(i) { continue }
                    self.remaining -= 1usize
                    return present(unsafe { mut (*map.entries.as_mut_ptr().add(i)).value })
                }
                none
            },
            none => none
        }
    }
    fn size_hint(): (usize, usize?) {
        (self.remaining, present(self.remaining))
    }
}
extend<region r, K, V, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements BidirectionalIterator {
    mut fn next_back(): (mut V from r)? {
        match mut self.map {
            present(map) => {
                while self.index < self.back {
                    self.back -= 1usize
                    if !map.entries.occupied(self.back) { continue }
                    self.remaining -= 1usize
                    return present(unsafe { mut (*map.entries.as_mut_ptr().add(self.back)).value })
                }
                none
            },
            none => none
        }
    }
}
extend<region r, K, V, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements ExactSizeIterator {}
extend<region r, K, V, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements Default {
    static fn default(): ValuesMut<region r, K, V, A, S> { ValuesMut(none, 0usize, 0usize, 0usize) }
}
extend<region r, K, V: fmt.Debug, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("ValuesMut(")
        try f.debug_open("[")
        match read self.map {
            present(map) => {
                var index = self.index
                var first = true
                while index < self.back {
                    if !map.entries.occupied(index) { index += 1usize; continue }
                    try f.debug_item_start(first)
                    try V.(fmt.Debug).fmt(map.entries[index].value, mut f)
                    try f.debug_item_end()
                    first = false
                    index += 1usize
                }
            },
            none => {}
        }
        try f.debug_close("]", self.size_hint().0 == 0usize)
        try f.write_str(")")
    }
}
// Borrowed iterators over the keys or the values only.
pub type Keys<region r, K, V> {
    inner: Iter<region r, K, V>
}
extend<region r, K, V> Keys<region r, K, V> implements Iterator {
    type Item = read K from r
    mut fn next(): (read K from r)? {
        match self.inner.next() {
            present(entry) => present(read entry.key),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) {
        self.inner.size_hint()
    }
}
extend<region r, K, V> Keys<region r, K, V> implements Clone {
    fn clone(): Keys<region r, K, V> { Keys(self.inner.clone()) }
}
extend<region r, K, V> Keys<region r, K, V> implements Default {
    static fn default(): Keys<region r, K, V> { Keys(Iter<region r, K, V>.(Default).default()) }
}
extend<region r, K: fmt.Debug, V> Keys<region r, K, V> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Keys(")
        try f.debug_open("[")
        var first = true
        for key in self.clone() {
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(key, mut f)
            try f.debug_item_end()
            first = false
        }
        try f.debug_close("]", first)
        try f.write_str(")")
    }
}
extend<region r, K, V> Keys<region r, K, V> implements ExactSizeIterator {}
pub type Values<region r, K, V> {
    inner: Iter<region r, K, V>
}
extend<region r, K, V> Values<region r, K, V> implements Iterator {
    type Item = read V from r
    mut fn next(): (read V from r)? {
        match self.inner.next() {
            present(entry) => present(read entry.value),
            none => none
        }
    }
    fn size_hint(): (usize, usize?) {
        self.inner.size_hint()
    }
}
extend<region r, K, V, A: Allocator> MapDrain<region r, K, V, A> implements FusedIterator {}
extend<region r, K: Hash + PartialEq, V, A: Allocator, S: BuildHasher, F: mut fn(read K, mut V): bool> ExtractIf<region r, K, V, A, S, F> implements FusedIterator {}
extend<region r, K, A: Allocator> SetDrain<region r, K, A> implements FusedIterator {}
extend<region r, K: Hash + PartialEq, A: Allocator, S: BuildHasher, F: mut fn(read K): bool> SetExtractIf<region r, K, A, S, F> implements FusedIterator {}
extend<region r, K: Hash + PartialEq, A: Allocator, S: BuildHasher> SetAlgebra<region r, K, A, S> implements FusedIterator {}
extend<region r, K, V> Iter<region r, K, V> implements FusedIterator {}
extend<K, V, A: Allocator, S: BuildHasher> MapIntoIter<K, V, A, S> implements FusedIterator {}
extend<K, V, A: Allocator, S: BuildHasher> IntoKeys<K, V, A, S> implements FusedIterator {}
extend<K, V, A: Allocator, S: BuildHasher> IntoValues<K, V, A, S> implements FusedIterator {}
extend<K, A: Allocator, S: BuildHasher> SetIntoIter<K, A, S> implements FusedIterator {}
extend<region r, K, V, A: Allocator, S: BuildHasher> IterMut<region r, K, V, A, S> implements FusedIterator {}
extend<region r, K, V, A: Allocator, S: BuildHasher> ValuesMut<region r, K, V, A, S> implements FusedIterator {}
extend<region r, K, V> Keys<region r, K, V> implements FusedIterator {}
extend<region r, K, V> Values<region r, K, V> implements FusedIterator {}
extend<region r, K, V> Values<region r, K, V> implements Clone {
    fn clone(): Values<region r, K, V> { Values(self.inner.clone()) }
}
extend<region r, K, V> Values<region r, K, V> implements Default {
    static fn default(): Values<region r, K, V> { Values(Iter<region r, K, V>.(Default).default()) }
}
extend<region r, K, V: fmt.Debug> Values<region r, K, V> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("Values(")
        try f.debug_open("[")
        var first = true
        for value in self.clone() {
            try f.debug_item_start(first)
            try V.(fmt.Debug).fmt(value, mut f)
            try f.debug_item_end()
            first = false
        }
        try f.debug_close("]", first)
        try f.write_str(")")
    }
}
extend<region r, K, V> Values<region r, K, V> implements ExactSizeIterator {}
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub fn keys(): Keys<region self, K, V> {
        Keys(self.entries.iter())
    }
    pub fn values(): Values<region self, K, V> {
        Values(self.entries.iter())
    }
}
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements MutableIterable {
    type Item = V
    type IterMut<region r> = ValuesMut<region r, K, V, A, S>
    fn iter_mut<region r>(receiver mut self: Self from r): ValuesMut<region r, K, V, A, S> {
        let back = self.entries.cap
        let remaining = self.entries.count
        ValuesMut(present(mut self), 0usize, back, remaining)
    }
}
extend<K, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub mut fn values_mut(): ValuesMut<region self, K, V, A, S> {
        let back = self.entries.cap
        let remaining = self.entries.count
        ValuesMut(present(mut self), 0usize, back, remaining)
    }
}

extend<K: Hash + PartialEq, V, A: Allocator + Default, S: BuildHasher + Default> Map<K, V, A, S> implements Default {
    static fn default(): Map<K, V, A, S> {
        Map<K, V, A, S>(allocator: A.(Default).default(), builder: S.(Default).default())
    }
}

extend<K: Hash + PartialEq + Clone, V: Clone, A: Allocator + Clone, S: BuildHasher + Clone> Map<K, V, A, S> implements Clone {
    fn clone(): Map<K, V, A, S> {
        var out = Map<K, V, A, S>(allocator: A.(Clone).clone(self.entries.allocator()), builder: self.builder.clone())
        var i = 0usize
        while i < self.entries.cap {
            if !self.entries.occupied(i) { i += 1usize; continue }
            let e = read self.entries[i]
            let old = out.insert(e.key.clone(), e.value.clone())
            i += 1usize
        }
        out
    }
}
// Equal when both hold the same keys with equal values, in any order.
extend<K: Hash + PartialEq, V: PartialEq, A: Allocator, S: BuildHasher, U: BuildHasher> Map<K, V, A, S> implements PartialEq<Map<K, V, A, U>> {
    fn eq(read other: Map<K, V, A, U>): bool {
        if self.len() != other.len() { return false }
        var i = 0usize
        while i < self.entries.cap {
            if !self.entries.occupied(i) { i += 1usize; continue }
            let e = read self.entries[i]
            match other.find_entry(e.key) {
                present(s) => { if !e.value.eq(other.entries[s].value) { return false } },
                none => { return false }
            }
            i += 1usize
        }
        true
    }
}
extend<K: Hash + PartialEq, V: Eq, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements Eq {}
extend<K: fmt.Debug, V: fmt.Debug, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.debug_open("{")
        var first = true
        for e in self.entries.iter() {
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(e.key, mut f)
            try f.write_str(": ")
            try V.(fmt.Debug).fmt(e.value, mut f)
            try f.debug_item_end()
            first = false
        }
        try f.debug_close("}", first)
    }
}
extend<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> implements ExtendItems<(K, V)> {
    mut fn extend<I: OwnedIterable<Item = (K, V)>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() {
                present(pair) => { let old = self.insert(pair.0, pair.1) },
                none => { break }
            }
        }
    }
}
extend<K: Hash + PartialEq, V> Map<K, V> implements FromItems<(K, V)> {
    static fn from_iter<I: OwnedIterable<Item = (K, V)>>(take items: I): Map<K, V> {
        var out = new<K, V>()
        out.extend(items)
        out
    }
}

extend<K: Hash + PartialEq, V, const N: usize> Map<K, V> implements core.convert.From<[(K, V); N]> {
    static fn from(take items: [(K, V); N]): Map<K, V> {
        var out = new<K, V>()
        for item in take items { let _ = out.insert(item.0, item.1) }
        out
    }
}

extend<K: Hash + PartialEq + Clone, A: Allocator + Clone, S: BuildHasher + Clone> Set<K, A, S> implements Clone {
    fn clone(): Set<K, A, S> { set_from_map(self.map.clone()) }
}
extend<K: Hash + PartialEq, A: Allocator + Default, S: BuildHasher + Default> Set<K, A, S> implements Default {
    static fn default(): Set<K, A, S> { set_from_map(Map<K, Unit, A, S>.(Default).default()) }
}

// The operators build new sets from clones of the operands' elements, as the
// `&a | &b` forms of the baseline do.
extend<K: Hash + PartialEq + Clone, A: Allocator + Clone, S: BuildHasher + Clone> Set<K, A, S> implements BitOr<Set<K, A, S>> {
    type Output = Set<K, A, S>
    fn bitor(read rhs: Set<K, A, S>): Set<K, A, S> {
        var out = self.clone()
        var i = 0usize
        while i < rhs.map.entries.cap {
            if !rhs.map.entries.occupied(i) { i += 1usize; continue }
            out.insert(rhs.map.entries[i].key.clone())
            i += 1usize
        }
        out
    }
}
extend<K: Hash + PartialEq + Clone, A: Allocator + Clone, S: BuildHasher + Clone> Set<K, A, S> implements BitAnd<Set<K, A, S>> {
    type Output = Set<K, A, S>
    fn bitand(read rhs: Set<K, A, S>): Set<K, A, S> {
        var out = set_from_map(Map<K, Unit, A, S>(allocator: A.(Clone).clone(self.map.allocator()), builder: S.(Clone).clone(self.map.hasher())))
        var i = 0usize
        while i < self.map.entries.cap {
            if !self.map.entries.occupied(i) { i += 1usize; continue }
            if rhs.contains(self.map.entries[i].key) {
                let _ = out.insert(self.map.entries[i].key.clone())
            }
            i += 1usize
        }
        out
    }
}
extend<K: Hash + PartialEq + Clone, A: Allocator + Clone, S: BuildHasher + Clone> Set<K, A, S> implements Sub<Set<K, A, S>> {
    type Output = Set<K, A, S>
    fn sub(read rhs: Set<K, A, S>): Set<K, A, S> {
        var out = set_from_map(Map<K, Unit, A, S>(allocator: A.(Clone).clone(self.map.allocator()), builder: S.(Clone).clone(self.map.hasher())))
        var i = 0usize
        while i < self.map.entries.cap {
            if !self.map.entries.occupied(i) { i += 1usize; continue }
            if !rhs.contains(self.map.entries[i].key) {
                let _ = out.insert(self.map.entries[i].key.clone())
            }
            i += 1usize
        }
        out
    }
}
extend<K: Hash + PartialEq + Clone, A: Allocator + Clone, S: BuildHasher + Clone> Set<K, A, S> implements BitXor<Set<K, A, S>> {
    type Output = Set<K, A, S>
    fn bitxor(read rhs: Set<K, A, S>): Set<K, A, S> {
        var out = set_from_map(Map<K, Unit, A, S>(allocator: A.(Clone).clone(self.map.allocator()), builder: S.(Clone).clone(self.map.hasher())))
        var i = 0usize
        while i < self.map.entries.cap {
            if !self.map.entries.occupied(i) { i += 1usize; continue }
            if !rhs.contains(self.map.entries[i].key) {
                let _ = out.insert(self.map.entries[i].key.clone())
            }
            i += 1usize
        }
        i = 0usize
        while i < rhs.map.entries.cap {
            if !rhs.map.entries.occupied(i) { i += 1usize; continue }
            if !self.contains(rhs.map.entries[i].key) {
                let _ = out.insert(rhs.map.entries[i].key.clone())
            }
            i += 1usize
        }
        out
    }
}

extend<region r, region s, K: Hash + PartialEq + Clone, A: Allocator + Default, S: BuildHasher + Default>
    read Set<K, A, S> from r implements BitOr<read Set<K, A, S> from s> {
    type Output = Set<K, A, S>
    fn bitor(read rhs: read Set<K, A, S> from s): Set<K, A, S> {
        var out = set_with_capacity_and_hasher_in<K, A, S>(
            self.len(),
            A.(Default).default(),
            S.(Default).default()
        )
        for key in self.iter() { let _ = out.insert(K.(Clone).clone(key)) }
        for key in rhs.iter() { let _ = out.insert(K.(Clone).clone(key)) }
        out
    }
}
extend<region r, region s, K: Hash + PartialEq + Clone, A: Allocator + Default, S: BuildHasher + Default>
    read Set<K, A, S> from r implements BitAnd<read Set<K, A, S> from s> {
    type Output = Set<K, A, S>
    fn bitand(read rhs: read Set<K, A, S> from s): Set<K, A, S> {
        var out = set_with_capacity_and_hasher_in<K, A, S>(
            self.len(),
            A.(Default).default(),
            S.(Default).default()
        )
        for key in self.iter() {
            if rhs.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        out
    }
}
extend<region r, region s, K: Hash + PartialEq + Clone, A: Allocator + Default, S: BuildHasher + Default>
    read Set<K, A, S> from r implements Sub<read Set<K, A, S> from s> {
    type Output = Set<K, A, S>
    fn sub(read rhs: read Set<K, A, S> from s): Set<K, A, S> {
        var out = set_with_capacity_and_hasher_in<K, A, S>(
            self.len(),
            A.(Default).default(),
            S.(Default).default()
        )
        for key in self.iter() {
            if !rhs.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        out
    }
}
extend<region r, region s, K: Hash + PartialEq + Clone, A: Allocator + Default, S: BuildHasher + Default>
    read Set<K, A, S> from r implements BitXor<read Set<K, A, S> from s> {
    type Output = Set<K, A, S>
    fn bitxor(read rhs: read Set<K, A, S> from s): Set<K, A, S> {
        var out = set_with_capacity_and_hasher_in<K, A, S>(
            self.len(),
            A.(Default).default(),
            S.(Default).default()
        )
        for key in self.iter() {
            if !rhs.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        for key in rhs.iter() {
            if !self.contains(key) { let _ = out.insert(K.(Clone).clone(key)) }
        }
        out
    }
}
// Equal when both hold the same elements, in any order.
extend<K: Hash + PartialEq, A: Allocator, S: BuildHasher, U: BuildHasher> Set<K, A, S> implements PartialEq<Set<K, A, U>> {
    fn eq(read other: Set<K, A, U>): bool {
        if self.len() != other.len() { return false }
        var i = 0usize
        while i < self.map.entries.cap {
            if !self.map.entries.occupied(i) { i += 1usize; continue }
            match other.map.find_entry(self.map.entries[i].key) {
                present(_) => {},
                none => { return false }
            }
            i += 1usize
        }
        true
    }
}
extend<K: Hash + PartialEq, A: Allocator, S: BuildHasher> Set<K, A, S> implements Eq {}
extend<K: fmt.Debug, A: Allocator, S: BuildHasher> Set<K, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.debug_open("{")
        var first = true
        for entry in self.map.entries.iter() {
            try f.debug_item_start(first)
            try K.(fmt.Debug).fmt(entry.key, mut f)
            try f.debug_item_end()
            first = false
        }
        try f.debug_close("}", first)
    }
}
extend<K: Hash + PartialEq, A: Allocator, S: BuildHasher> Set<K, A, S> implements ExtendItems<K> {
    mut fn extend<I: OwnedIterable<Item = K>>(take items: I): Unit {
        var source = items.into_iter()
        while true {
            match take source.next() { present(item) => { let added = self.insert(item) }, none => { break } }
        }
    }
}
extend<K: Hash + PartialEq> Set<K> implements FromItems<K> {
    static fn from_iter<I: OwnedIterable<Item = K>>(take items: I): Set<K> {
        var out = set_new<K>()
        out.extend(items)
        out
    }
}

extend<K: Hash + PartialEq, const N: usize> Set<K> implements core.convert.From<[K; N]> {
    static fn from(take items: [K; N]): Set<K> {
        var out = set_new<K>()
        for item in take items { let _ = out.insert(item) }
        out
    }
}

// Owned storage moves or is shared exactly when its elements and allocator do.
unsafe extend<K: Transferable, V: Transferable, A: Allocator + Transferable, S: BuildHasher + Transferable> Map<K, V, A, S> implements Transferable {}
unsafe extend<K: Shareable, V: Shareable, A: Allocator + Shareable, S: BuildHasher + Shareable> Map<K, V, A, S> implements Shareable {}
unsafe extend<region r, K: Transferable, V: Transferable, A: Allocator + Transferable> MapDrain<region r, K, V, A> implements Transferable {}
unsafe extend<region r, K: Shareable, V: Shareable, A: Allocator + Shareable> MapDrain<region r, K, V, A> implements Shareable {}

// An entry owns the query key and exclusively borrows its map until consumed.
// The occupied index remains valid because the loan excludes map mutation.
pub type OccupiedEntry<region r, K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    map: mut Map<K, V, A, S> from r
    index: usize
}
pub type VacantEntry<region r, K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    map: mut Map<K, V, A, S> from r
    key: K
}
pub enum Entry<region r, K, V, A: Allocator = Global, S: BuildHasher = DefaultHashBuilder> {
    Occupied(OccupiedEntry<region r, K, V, A, S>);
    Vacant(VacantEntry<region r, K, V, A, S>)
}

extend<K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> Map<K, V, A, S> {
    pub mut fn entry(take key: K): Entry<region self, K, V, A, S> {
        match self.find_entry(key) {
            present(index) => Entry.Occupied(OccupiedEntry(mut self, index)),
            none => Entry.Vacant(VacantEntry(mut self, key))
        }
    }
}

extend<region r, K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> OccupiedEntry<region r, K, V, A, S> {
    pub fn key(): read K from self { read self.map.entries[self.index].key }
    pub fn get(): read V from self { read self.map.entries[self.index].value }
    // The exclusive map loan preserves this initialized index; the returned
    // view cannot outlive this reborrow of the entry.
    pub mut fn get_mut(): mut V from self {
        unsafe { mut (*self.map.entries.as_mut_ptr().add(self.index)).value }
    }
    pub mut fn insert(take value: V): V {
        let slot = unsafe { core.ptr.from_mut((*self.map.entries.as_mut_ptr().add(self.index)).value) }
        unsafe { core.ptr.replace(slot, value) }
    }
    pub take fn into_mut(): mut V from r {
        unsafe { mut (*self.map.entries.as_mut_ptr().add(self.index)).value }
    }
    pub take fn remove(): V {
        self.map.remove_index(self.index).1
    }
}

extend<region r, K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> VacantEntry<region r, K, V, A, S> {
    pub take fn insert(take value: V): mut V from r {
        let slot = self.map.or_insert(self.key, value)
        // The returned pointer is to the inserted value; the exclusive map
        // loan outlives this consumed entry and prevents reallocations.
        let p = core.ptr.from_mut(*slot)
        unsafe { mut *p }
    }
}
extend<region r, K: Hash + PartialEq + fmt.Debug, V: fmt.Debug, A: Allocator, S: BuildHasher> OccupiedEntry<region r, K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("OccupiedEntry")
        try debug.field("key", self.key())
        try debug.field("value", self.get())
        try debug.finish_non_exhaustive()
    }
}
extend<region r, K: Hash + PartialEq + fmt.Debug, V, A: Allocator, S: BuildHasher> VacantEntry<region r, K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        var debug = try f.debug_struct("VacantEntry")
        try debug.field("key", read self.key)
        try debug.finish_non_exhaustive()
    }
}

extend<region r, K: Hash + PartialEq, V, A: Allocator, S: BuildHasher> Entry<region r, K, V, A, S> {
    pub fn key(): read K from self {
        match self {
            Entry.Occupied(entry) => entry.key(),
            Entry.Vacant(entry) => read entry.key
        }
    }
    pub take fn or_insert(take value: V): mut V from r {
        match take self {
            Entry.Occupied(entry) => entry.into_mut(),
            Entry.Vacant(entry) => entry.insert(value)
        }
    }
    pub take fn or_insert_with<F: take fn(): V>(take make: F): mut V from r {
        match take self {
            Entry.Occupied(entry) => entry.into_mut(),
            Entry.Vacant(entry) => entry.insert(make())
        }
    }
    pub take fn or_insert_with_key<F: take fn(read K): V>(take make: F): mut V from r {
        match take self {
            Entry.Occupied(entry) => entry.into_mut(),
            Entry.Vacant(entry) => {
                let value = make(read entry.key)
                entry.insert(value)
            }
        }
    }
    pub take fn insert_entry(take value: V): OccupiedEntry<region r, K, V, A, S> {
        match take self {
            Entry.Occupied(entry) => {
                var occupied = entry
                let _old = occupied.insert(value)
                occupied
            },
            Entry.Vacant(entry) => {
                let hash = entry.map.builder.hash_one(entry.key)
                let found = entry.map.find_pos(hash, entry.key)
                let index = match found.1 {
                    present(index) => {
                        let pointer = unsafe { core.ptr.from_mut((*entry.map.entries.ptr.add(index)).value) }
                        let _old = unsafe { core.ptr.replace(pointer, value) }
                        index
                    },
                    none => match capture entry.map.try_append(hash, entry.key, value, found.0) {
                        success(index) => index,
                        failure(error) => error.handle()
                    }
                }
                OccupiedEntry(entry.map, index)
            }
        }
    }
    pub take fn and_modify<F: take fn(mut V): Unit>(take modify: F): Entry<region r, K, V, A, S> {
        match take self {
            Entry.Occupied(entry) => {
                var occupied = entry
                modify(occupied.get_mut())
                Entry.Occupied(occupied)
            },
            Entry.Vacant(entry) => Entry.Vacant(entry)
        }
    }
}

extend<region r, K: Hash + PartialEq, V: Default, A: Allocator, S: BuildHasher> Entry<region r, K, V, A, S> {
    pub take fn or_default(): mut V from r {
        self.or_insert_with(take fn(): V { V.(Default).default() })
    }
}

extend<region r, K: Hash + PartialEq + fmt.Debug, V: fmt.Debug, A: Allocator, S: BuildHasher> Entry<region r, K, V, A, S> implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        match self {
            Entry.Occupied(entry) => {
                try f.write_str("Occupied(")
                try K.(fmt.Debug).fmt(entry.key(), mut f)
                try f.write_str(": ")
                try V.(fmt.Debug).fmt(entry.get(), mut f)
                try f.write_str(")")
            },
            Entry.Vacant(entry) => {
                try f.write_str("Vacant(")
                try K.(fmt.Debug).fmt(entry.key, mut f)
                try f.write_str(")")
            }
        }
    }
}
