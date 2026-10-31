import std.sync.{mutex, mpsc}
import core.fmt
import core.fmt.{Debug, Display}
import alloc.string

fn debug<T: Debug>(value: read T): string.String throws fmt.Error {
    var output = string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        try T.(Debug).fmt(value, mut formatter)
    }
    output
}

fn display<T: Display>(value: read T): string.String throws fmt.Error {
    var output = string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        try T.(Display).fmt(value, mut formatter)
    }
    output
}

fn check(): i32 throws fmt.Error {
    if (try display(mpsc.RecvError())).as_text() != "receiving on a closed channel" { return 1 }
    if (try debug(mpsc.RecvError())).as_text() != "RecvError" { return 2 }
    if (try display(mpsc.TryRecvError(false))).as_text() != "receiving on an empty channel" { return 3 }
    if (try debug(mpsc.TryRecvError(false))).as_text() != "Empty" { return 4 }
    if (try debug(mpsc.TryRecvError(true))).as_text() != "Disconnected" { return 5 }
    if (try display(mpsc.RecvTimeoutError(true, false))).as_text() != "timed out waiting on channel" { return 6 }
    if (try debug(mpsc.RecvTimeoutError(true, false))).as_text() != "Timeout" { return 7 }
    if (try debug(mpsc.RecvTimeoutError(false, true))).as_text() != "Disconnected" { return 8 }
    if (try display(mpsc.SendError(5))).as_text() != "sending on a closed channel" { return 9 }
    if (try debug(mpsc.SendError(5))).as_text() != "SendError { .. }" { return 10 }
    if (try debug(mpsc.TrySendError(5, false))).as_text() != "Full(..)" { return 11 }
    if (try display(mpsc.TrySendError(5, true))).as_text() != "sending on a closed channel" { return 12 }
    if (try display(mutex.PoisonError(1))).as_text() != "poisoned lock: another task failed inside" { return 13 }
    if (try debug(mutex.PoisonError(1))).as_text() != "PoisonError { .. }" { return 14 }
    let blocked = mutex.TryLockError<i32>.WouldBlock
    if (try debug(blocked)).as_text() != "WouldBlock" { return 15 }
    if (try display(blocked)).as_text() != "try_lock failed because the operation would block" { return 16 }
    let poisoned = mutex.TryLockError<i32>.Poisoned(3)
    if (try debug(poisoned)).as_text() != "Poisoned(..)" { return 17 }
    if (try debug(mpsc.SendTimeoutError(5, true, false))).as_text() != "Timeout(..)" { return 18 }
    if (try debug(mpsc.SendTimeoutError(5, false, true))).as_text() != "Disconnected(..)" { return 19 }
    if (try display(mpsc.SendTimeoutError(5, true, false))).as_text() != "timed out waiting on channel" { return 20 }
    if (try display(mpsc.SendTimeoutError(5, false, true))).as_text() != "sending on a closed channel" { return 21 }
    0
}

fn main(): i32 {
    match capture check() { success(result) => result, failure(_) => 99 }
}
