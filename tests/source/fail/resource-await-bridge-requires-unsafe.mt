// expect-error: unsafe 14:13 requires an unsafe block
import core.future.{Context, Future, Poll}

type Pending {}
extend Pending implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut context: Context): Poll<Unit> {
        Poll.Pending
    }
}

fn main(): i32 {
    var future = Pending()
    let _ = core.future.poll_await(mut future, core.ptr.null_mut<u8>())
    0
}
