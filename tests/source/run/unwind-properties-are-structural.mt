import core.marker.Unpin
import alloc.alloc.{AllocError, Allocator, Global, Layout}
import std.panic.AssertUnwindSafe
import std.panic.{RefUnwindSafe, UnwindSafe}

type Payload { value: i32 }
type Nested<T> { value: T }

type ImmovableAllocator { inner: Global }
extend ImmovableAllocator not Unpin

unsafe extend ImmovableAllocator implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        try self.inner.allocate(layout)
    }
    mut unsafe fn deallocate(p: ptr<mut u8>, layout: Layout): Unit {
        unsafe { self.inner.deallocate(p, layout) }
    }
    mut unsafe fn grow(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        unsafe { try self.inner.grow(p, old, new_size) }
    }
    mut unsafe fn shrink(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        unsafe { try self.inner.shrink(p, old, new_size) }
    }
}

fn unpin<T: Unpin>() {}
fn unwind_safe<T: UnwindSafe>() {}
fn ref_unwind_safe<T: RefUnwindSafe>() {}
fn transferable<T: Transferable>() {}
fn shareable<T: Shareable>() {}
fn require_copy<T: Copy>() {}
fn require_clone<T: core.clone.Clone>() {}
fn require_partial_eq<T: core.cmp.PartialEq>() {}
fn require_eq<T: core.cmp.Eq>() {}
fn require_partial_ord<T: core.cmp.PartialOrd>() {}
fn require_ord<T: core.cmp.Ord>() {}
fn require_hash<T: core.hash.Hash>() {}
fn require_default<T: core.default.Default>() {}
fn require_debug<T: core.fmt.Debug>() {}

fn phantom_data_value_traits<T: unsized>() {
    require_copy<core.marker.PhantomData<T>>()
    require_clone<core.marker.PhantomData<T>>()
    require_partial_eq<core.marker.PhantomData<T>>()
    require_eq<core.marker.PhantomData<T>>()
    require_partial_ord<core.marker.PhantomData<T>>()
    require_ord<core.marker.PhantomData<T>>()
    require_hash<core.marker.PhantomData<T>>()
    require_default<core.marker.PhantomData<T>>()
    require_debug<core.marker.PhantomData<T>>()
    require_copy<core.iter.Phantom<T>>()
}

fn phantom_data_marker_properties<T: unsized + Transferable + Shareable + Unpin + UnwindSafe + RefUnwindSafe>() {
    unpin<core.marker.PhantomData<T>>()
    unwind_safe<core.marker.PhantomData<T>>()
    ref_unwind_safe<core.marker.PhantomData<T>>()
    unpin<core.iter.Phantom<T>>()
    unwind_safe<core.iter.Phantom<T>>()
    ref_unwind_safe<core.iter.Phantom<T>>()
}

fn phantom_data_transferable<T: unsized + Transferable>() {
    transferable<core.marker.PhantomData<T>>()
}

fn phantom_data_shareable<T: unsized + Shareable>() {
    shareable<core.marker.PhantomData<T>>()
}

fn assert_unwind_safe_traits<T>() {
    unwind_safe<AssertUnwindSafe<T>>()
    ref_unwind_safe<AssertUnwindSafe<T>>()
}

fn reference_unwind_properties<region r, T: RefUnwindSafe>() {
    ref_unwind_safe<read T from r>()
    ref_unwind_safe<mut T from r>()
    ref_unwind_safe<ptr<read T>>()
    ref_unwind_safe<ptr<mut T>>()
}

fn boxed_transferable<T: unsized + Transferable, A: Allocator + Transferable>() {
    transferable<alloc.boxed.Box<T, A>>()
    transferable<alloc.boxed.Pinned<T, A>>()
}

fn boxed_shareable<T: unsized + Shareable, A: Allocator + Shareable>() {
    shareable<alloc.boxed.Box<T, A>>()
    shareable<alloc.boxed.Pinned<T, A>>()
}

fn pinned_box_unwind_safe<T: unsized + UnwindSafe, A: Allocator + UnwindSafe>() {
    unwind_safe<alloc.boxed.Pinned<T, A>>()
}

fn pinned_box_ref_unwind_safe<T: unsized + RefUnwindSafe, A: Allocator + RefUnwindSafe>() {
    ref_unwind_safe<alloc.boxed.Pinned<T, A>>()
}

fn mutable_slice_iterator_is_ref_unwind_safe<region r, T: RefUnwindSafe>() {
    ref_unwind_safe<core.slice.SliceIterMut<region r, T>>()
}

fn mutable_io_slice_is_ref_unwind_safe<region r>() {
    ref_unwind_safe<std.io.IoSliceMut<region r>>()
}

fn mutable_drain_unwind_properties<region r, T: RefUnwindSafe, A: alloc.alloc.Allocator + RefUnwindSafe>() {
    unwind_safe<alloc.vec.Drain<region r, T, A>>()
    ref_unwind_safe<alloc.vec.Drain<region r, T, A>>()
}

fn btree_range_unwind_properties<region r, K: RefUnwindSafe, V: RefUnwindSafe, A: alloc.alloc.Allocator>() {
    unwind_safe<alloc.btree.KeyRange<region r, K, V, A>>()
    ref_unwind_safe<alloc.btree.KeyRange<region r, K, V, A>>()
    unwind_safe<alloc.btree.RangeMut<region r, K, V, A>>()
    ref_unwind_safe<alloc.btree.RangeMut<region r, K, V, A>>()
}

fn range_unwind_properties<T: UnwindSafe + RefUnwindSafe>() {
    unwind_safe<core.iter.RangeFrom<T>>()
    ref_unwind_safe<core.iter.RangeFrom<T>>()
    unwind_safe<core.iter.Range<T>>()
    ref_unwind_safe<core.iter.Range<T>>()
    unwind_safe<core.iter.RangeTo<T>>()
    ref_unwind_safe<core.iter.RangeTo<T>>()
    unwind_safe<core.iter.RangeToInclusive<T>>()
    ref_unwind_safe<core.iter.RangeToInclusive<T>>()
    unwind_safe<core.iter.RangeInclusive<T>>()
    ref_unwind_safe<core.iter.RangeInclusive<T>>()
    unwind_safe<core.iter.RangeFull>()
    ref_unwind_safe<core.iter.RangeFull>()
}

fn local_key_marker_properties<T>() {
    unpin<std.sync.tls.LocalKey<T>>()
    unwind_safe<std.sync.tls.LocalKey<T>>()
    ref_unwind_safe<std.sync.tls.LocalKey<T>>()
}

fn main(): i32 {
    phantom_data_value_traits<i32>()
    phantom_data_marker_properties<i32>()
    phantom_data_transferable<[i32]>()
    phantom_data_shareable<[i32]>()
    unpin<Nested<Payload>>()
    unpin<alloc.boxed.Box<i32, ImmovableAllocator>>()
    unpin<alloc.rc.Rc<i32, ImmovableAllocator>>()
    unpin<alloc.arc.Arc<i32, ImmovableAllocator>>()
    unwind_safe<Nested<Payload>>()
    ref_unwind_safe<Nested<Payload>>()
    unwind_safe<core.cell.Cell<i32>>()
    assert_unwind_safe_traits<core.cell.Cell<i32>>()
    unpin<Never>()
    unwind_safe<Never>()
    ref_unwind_safe<Never>()
    0
}
