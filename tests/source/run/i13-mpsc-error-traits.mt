import std.sync.mpsc
import core.convert.From
import core.clone.Clone
import core.cmp.Eq

fn require_eq<T: Eq>(read value: T): Unit {}

fn main(): i32 {
    let send_error = mpsc.SendError(7i32)
    let equal_send_error = mpsc.SendError(7i32)
    let different_send_error = mpsc.SendError(8i32)
    if send_error != equal_send_error { return 1 }
    if send_error == different_send_error { return 2 }
    require_eq(read send_error)

    let disconnected = mpsc.TrySendError(7i32, true)
    let equal_disconnected = mpsc.TrySendError(7i32, true)
    let full = mpsc.TrySendError(7i32, false)
    if disconnected != equal_disconnected { return 3 }
    if disconnected == full { return 4 }
    require_eq(read disconnected)

    let converted: mpsc.TrySendError<i32> =
        mpsc.TrySendError<i32>.(From<mpsc.SendError<i32>>).from(mpsc.SendError(9i32))
    if converted.value != 9i32 || !converted.disconnected { return 5 }

    let recv_error = mpsc.RecvError()
    if recv_error.clone() != recv_error { return 6 }
    require_eq(read recv_error)

    let retry = mpsc.TryRecvError(false)
    if retry.clone() != retry || retry == mpsc.TryRecvError(true) { return 7 }
    require_eq(read retry)

    let timed_out = mpsc.RecvTimeoutError(true, false)
    if timed_out.clone() != timed_out ||
        timed_out == mpsc.RecvTimeoutError(false, false) ||
        timed_out == mpsc.RecvTimeoutError(true, true) {
        return 8
    }
    require_eq(read timed_out)

    let disconnected: mpsc.TryRecvError =
        mpsc.TryRecvError.(From<mpsc.RecvError>).from(mpsc.RecvError())
    if !disconnected.disconnected { return 9 }
    let disconnected_timeout: mpsc.RecvTimeoutError =
        mpsc.RecvTimeoutError.(From<mpsc.RecvError>).from(mpsc.RecvError())
    if disconnected_timeout.timed_out || !disconnected_timeout.disconnected { return 10 }
    0
}
