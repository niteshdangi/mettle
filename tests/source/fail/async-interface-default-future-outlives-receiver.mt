// expect-error: ownership 20:5 access or storage lifetime conflicts with a live read loan
import core.future.{Future, Poll, Context, noop_waker}

interface Sized2 {
    fn base<region r>(receiver read self: Self from r): i32
    async fn doubled<region r>(receiver read self: Self from r) {
        self.base() * 2
    }
}

type Number { value: i32 }
extend Number implements Sized2 {
    fn base<region r>(receiver read self: Self from r): i32 { self.value }
}

fn main(): i32 {
    let future = {
        let number = Number(21)
        number.doubled()
    }
    0
}
