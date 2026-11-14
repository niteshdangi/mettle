// The collection vocabulary: one implementation each, reexported from its
// owning module. `List`, `Map` and `Set` are also in the prelude.
pub import super.vec.List
pub import super.hash_map.{Map, Set}
pub import super.btree.{SortedMap, SortedSet}
pub import super.vec_deque.Deque
pub import super.linked_list.LinkedList
pub import super.binary_heap.BinaryHeap

import core.clone.Clone
import core.cmp.{Eq, PartialEq}
import core.fmt
import super.alloc.{AllocError, Layout, handle_alloc_error, layout_unchecked, panic_precondition}

copy enum ReserveErrorKind { CapacityOverflow, AllocError(AllocError) }
pub type TryReserveError { kind: ReserveErrorKind }

extend TryReserveError {
    pub(super) static fn capacity_overflow(): TryReserveError {
        TryReserveError(ReserveErrorKind.CapacityOverflow)
    }
    pub(super) static fn from_alloc_error(error: AllocError): TryReserveError {
        TryReserveError(ReserveErrorKind.AllocError(error))
    }
    pub(super) static fn allocation_error(layout: Layout): TryReserveError {
        TryReserveError.from_alloc_error(AllocError(layout.size(), layout.align()))
    }
    pub(super) fn handle(): Never {
        match self.kind {
            ReserveErrorKind.CapacityOverflow => panic_precondition(),
            ReserveErrorKind.AllocError(error) =>
                handle_alloc_error(unsafe { layout_unchecked(error.size, error.align) })
        }
    }
}
extend TryReserveError implements Clone {
    fn clone(): TryReserveError { TryReserveError(self.kind) }
}
extend TryReserveError implements PartialEq {
    fn eq(read other: TryReserveError): bool {
        match self.kind {
            ReserveErrorKind.CapacityOverflow => match other.kind {
                ReserveErrorKind.CapacityOverflow => true,
                ReserveErrorKind.AllocError(_) => false
            },
            ReserveErrorKind.AllocError(error) => match other.kind {
                ReserveErrorKind.CapacityOverflow => false,
                ReserveErrorKind.AllocError(other_error) =>
                    error.size == other_error.size && error.align == other_error.align
            }
        }
    }
}
extend TryReserveError implements Eq {}
extend TryReserveError implements fmt.Display {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("memory allocation failed")
        match self.kind {
            ReserveErrorKind.CapacityOverflow =>
                try f.write_str(" because the computed capacity exceeded the collection's maximum"),
            ReserveErrorKind.AllocError(_) =>
                try f.write_str(" because the memory allocator returned an error")
        }
    }
}
extend TryReserveError implements fmt.Debug {
    fn fmt(mut f: fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("TryReserveError { kind: ")
        match self.kind {
            ReserveErrorKind.CapacityOverflow => try f.write_str("CapacityOverflow"),
            ReserveErrorKind.AllocError(error) => {
                try f.write_str("AllocError { layout: Layout { size: ")
                try usize.(fmt.Debug).fmt(error.size, mut f)
                try f.write_str(", align: ")
                try usize.(fmt.Debug).fmt(error.align, mut f)
                try f.write_str(" } }")
            }
        }
        try f.write_str(" }")
    }
}
extend TryReserveError implements core.error.Error {}
