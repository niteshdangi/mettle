import core.cmp.{Ord, PartialEq}
import core.hash.{Hash, Hasher}
import std.io.ErrorKind

fn require_eq<T: core.cmp.Eq>(read value: T): Unit {}

fn main(): i32 {
    let kinds: [ErrorKind; 43] = [
        ErrorKind.NotFound, ErrorKind.PermissionDenied, ErrorKind.ConnectionRefused,
        ErrorKind.ConnectionReset, ErrorKind.ConnectionAborted, ErrorKind.NotConnected,
        ErrorKind.AddrInUse, ErrorKind.AddrNotAvailable, ErrorKind.BrokenPipe,
        ErrorKind.AlreadyExists, ErrorKind.WouldBlock, ErrorKind.InvalidInput,
        ErrorKind.TimedOut, ErrorKind.Interrupted, ErrorKind.OutOfMemory,
        ErrorKind.IsADirectory, ErrorKind.NotADirectory, ErrorKind.DirectoryNotEmpty,
        ErrorKind.Other, ErrorKind.InvalidData, ErrorKind.WriteZero,
        ErrorKind.UnexpectedEof, ErrorKind.Unsupported, ErrorKind.ArgumentListTooLong,
        ErrorKind.CrossesDevices, ErrorKind.Deadlock, ErrorKind.ExecutableFileBusy,
        ErrorKind.FileTooLarge, ErrorKind.FilesystemLoop, ErrorKind.HostUnreachable,
        ErrorKind.InProgress, ErrorKind.InputOutputError, ErrorKind.InvalidFilename,
        ErrorKind.NetworkDown, ErrorKind.NetworkUnreachable, ErrorKind.NotSeekable,
        ErrorKind.QuotaExceeded, ErrorKind.ReadOnlyFilesystem, ErrorKind.ResourceBusy,
        ErrorKind.StaleNetworkFileHandle, ErrorKind.StorageFull, ErrorKind.TooManyLinks,
        ErrorKind.TooManyOpenFiles
    ]
    if kinds.len() != 43usize { return 1 }
    let first = kinds[0usize]
    let copied = first
    require_eq(first)
    if first != copied || !first.is(copied) { return 2 }
    if !ErrorKind.NotFound.cmp(read ErrorKind.PermissionDenied).is_lt() { return 3 }

    var left = core.hash.fnv1a()
    ErrorKind.NotFound.hash(mut left)
    let left_hash = left.finish()
    var same = core.hash.fnv1a()
    ErrorKind.NotFound.hash(mut same)
    if left_hash != same.finish() { return 4 }
    var different = core.hash.fnv1a()
    ErrorKind.PermissionDenied.hash(mut different)
    if left_hash == different.finish() { return 5 }
    0
}
