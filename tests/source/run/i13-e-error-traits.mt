// expect-exit: 0
import core.clone.Clone
import core.ffi.{FromBytesUntilNulError, FromBytesWithNulError}
import core.future.{RawWaker, RawWakerVTable}
import core.hash.BuildHasherDefault
import core.slice.GetDisjointMutError
import core.text.Text
import std.env.VarError
import std.fs.FileTimes
import std.io.{Empty, SeekFrom}
import std.net.AddrParseError
import std.path.StripPrefixError
import std.process.ExitCode
import std.time.TryFromFloatSecsError

type NoTraitHasher {}

type BorrowedError<region r> { message: read Text from r }
extend<region r> BorrowedError<region r> implements core.fmt.Debug {
    fn fmt(mut f: core.fmt.Formatter): Unit throws core.fmt.Error {
        try f.write_str(self.message)
    }
}
extend<region r> BorrowedError<region r> implements core.fmt.Display {
    fn fmt(mut f: core.fmt.Formatter): Unit throws core.fmt.Error {
        try f.write_str(self.message)
    }
}
extend<region r> BorrowedError<region r> implements core.error.Error {}

fn box_borrowed_error<region r>(
    take error: BorrowedError<region r> from r
): alloc.boxed.Heap<any core.error.Error from r> {
    alloc.boxed.Heap<any core.error.Error from r>.(core.convert.From<BorrowedError<region r> from r>).from(error)
}

fn requires_eq<T: core.cmp.Eq>(read value: T): bool {
    value == value
}

unsafe fn clone_test_waker(data: ptr<mut u8>): RawWaker {
    RawWaker(data, test_waker_vtable())
}

unsafe fn noop_test_waker(data: ptr<mut u8>): Unit {}

fn test_waker_vtable(): RawWakerVTable {
    RawWakerVTable(clone_test_waker, noop_test_waker, noop_test_waker, noop_test_waker)
}

fn main(): i32 {
    let float_error = TryFromFloatSecsError()
    if float_error.clone() != TryFromFloatSecsError() { return 1 }
    if !requires_eq(float_error) { return 2 }

    let default_builder = BuildHasherDefault<NoTraitHasher>()
    if default_builder.clone() != BuildHasherDefault<NoTraitHasher>() { return 3 }
    if !requires_eq(default_builder) { return 4 }

    let exit_code = ExitCode(7u8)
    if exit_code.clone() != ExitCode(7u8) { return 5 }
    if exit_code == ExitCode(8u8) { return 6 }
    if !requires_eq(exit_code) { return 7 }

    let file_times = FileTimes.new()
    let _cloned_file_times = file_times.clone()
    let var_error = VarError.NotPresent
    if var_error.clone() != VarError.NotPresent { return 8 }
    if var_error == VarError.NotUnicode(std.ffi.os_string_from_text("bad")) { return 9 }
    if !requires_eq(var_error) { return 10 }

    let start = SeekFrom.Start(7u64)
    if start.clone() != SeekFrom.Start(7u64) { return 11 }
    if start == SeekFrom.End(7i64) { return 12 }
    if !requires_eq(start) { return 13 }

    let address_error = AddrParseError()
    if address_error != AddrParseError() { return 14 }
    if !requires_eq(address_error) { return 15 }

    let path_error = StripPrefixError()
    if path_error != StripPrefixError() { return 16 }
    if !requires_eq(path_error) { return 17 }

    let bounds_error = GetDisjointMutError.IndexOutOfBounds
    if bounds_error.clone() != GetDisjointMutError.IndexOutOfBounds { return 18 }
    if bounds_error != GetDisjointMutError.IndexOutOfBounds { return 19 }
    if bounds_error == GetDisjointMutError.OverlappingIndices { return 20 }
    if !requires_eq(bounds_error) { return 21 }

    let invalid_utf8 = match core.text.from_utf8([0xffu8]) {
        success(_) => { return 22 },
        failure(error) => error
    }
    let truncated_utf8 = match core.text.from_utf8([0xc2u8]) {
        success(_) => { return 23 },
        failure(error) => error
    }
    if invalid_utf8.clone() != invalid_utf8 { return 24 }
    if invalid_utf8 == truncated_utf8 { return 25 }
    if !requires_eq(invalid_utf8) { return 26 }

    let interior_nul = FromBytesWithNulError.InteriorNul(2usize)
    let same_position = FromBytesWithNulError.InteriorNul(2usize)
    let different_position = FromBytesWithNulError.InteriorNul(3usize)
    if interior_nul.clone() != same_position { return 27 }
    if interior_nul == different_position { return 28 }
    if interior_nul == FromBytesWithNulError.NotNulTerminated { return 29 }
    if !requires_eq(interior_nul) { return 30 }

    let no_nul = FromBytesUntilNulError()
    if no_nul.clone() != FromBytesUntilNulError() { return 31 }
    if !requires_eq(no_nul) { return 32 }

    let vtable = test_waker_vtable()
    if vtable.clone() != vtable { return 33 }
    let raw_waker = RawWaker(core.ptr.null_mut<u8>(), vtable)
    if raw_waker != RawWaker(core.ptr.null_mut<u8>(), vtable.clone()) { return 34 }

    let empty = Empty()
    if empty.clone() != Empty() { return 35 }

    match capture alloc.string.from_utf8(alloc.vec.from_array([0xffu8])) {
        success(_) => { return 36 },
        failure(error) => {
            if error.clone() != error || !requires_eq(error) { return 37 }
        }
    }
    match capture alloc.ffi.CString.new(alloc.vec.from_array([65u8, 0u8])) {
        success(_) => { return 38 },
        failure(error) => {
            if error.clone() != error || !requires_eq(error) { return 39 }
        }
    }
    match capture alloc.ffi.CString.from_vec_with_nul(
        alloc.vec.from_array([65u8, 0u8, 66u8])
    ) {
        success(_) => { return 40 },
        failure(error) => {
            if error.clone() != error || !requires_eq(error) { return 41 }
        }
    }
    let invalid_c_string = unsafe {
        alloc.ffi.CString.from_vec_unchecked(alloc.vec.from_array([0xffu8]))
    }
    match capture invalid_c_string.into_string() {
        success(_) => { return 42 },
        failure(error) => {
            if error.clone() != error || !requires_eq(error) { return 43 }
        }
    }

    let message_owner = alloc.string.from_text("borrowed error")
    let borrowed_error = box_borrowed_error(BorrowedError(message_owner.as_text()))
    if borrowed_error.get().source().is_present() { return 44 }

    0
}
