import alloc.alloc.AllocError
import alloc.ffi.{CString, NulError}
import alloc.vec
import core.convert.From
import core.cmp.Ord
import std.io.{Error, ErrorKind}
import std.fs.{TryLockError as FileLockError}

fn main(): i32 {
    assert(ErrorKind.HostUnreachable.cmp(read ErrorKind.ConnectionAborted).is_lt() &&
        ErrorKind.InvalidData.cmp(read ErrorKind.TimedOut).is_lt(),
        "portable error ordering follows the selected variant order")
    let allocation = Error.(From<AllocError>).from(AllocError(64usize, 8usize))
    assert(allocation.kind().is(ErrorKind.OutOfMemory), "allocation error kind")
    assert(allocation.raw_os_error().is_none() && allocation.get_ref().is_none(),
        "allocation failure needs no payload allocation")

    var bytes = vec.new<u8>()
    bytes.extend_from_slice("a\0b".as_bytes())
    let nul = match take capture CString.new(bytes) {
        failure(error) => error,
        success(_) => { return 1 }
    }
    let invalid = Error.(From<NulError>).from(nul)
    assert(invalid.kind().is(ErrorKind.InvalidInput) && invalid.raw_os_error().is_none(),
        "NUL error is invalid input, not an OS error")
    let retained = match take invalid.downcast<NulError>() {
        success(payload) => payload,
        failure(_) => { return 2 }
    }
    assert(retained.get().nul_position() == 1usize, "conversion preserves error identity")
    let original = retained.into_inner().into_vec()
    assert(original.as_slice() == "a\0b".as_bytes(), "conversion preserves owned bytes")

    let blocked = Error.(From<FileLockError>).from(FileLockError.WouldBlock)
    assert(blocked.kind().is(ErrorKind.WouldBlock) && blocked.raw_os_error().is_none(),
        "file lock contention has its own typed alternative")
    let lock_failure = FileLockError.Error(std.io.from_raw_os_error(13i32))
    assert(FileLockError.(core.error.Error).source(read lock_failure).is_present(),
        "file lock OS failure exposes its cause")
    let operating_system = Error.(From<FileLockError>).from(lock_failure)
    assert(operating_system.raw_os_error() == present(13i32),
        "file lock OS failure preserves its original error")
    0
}
