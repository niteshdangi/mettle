import core.future.{Future, Poll, Context, noop_waker}

interface ExplicitDefaultValue {
    async fn value<region r>(receiver read self: Self from r): i32 { 42 }
}

type ExplicitNumber { value: i32 }
extend ExplicitNumber implements ExplicitDefaultValue {
    async fn value<region r>(receiver read self: Self from r): i32 {
        self.value
    }
}

interface InferredDefaultValue {
    async fn value<region r>(receiver read self: Self from r) { 42 }
}

type InferredNumber {}
extend InferredNumber implements InferredDefaultValue {}

interface OverriddenDefaultValue {
    async fn value<region r>(receiver read self: Self from r) { 42 }
}

type OverriddenNumber { value: i32 }
extend OverriddenNumber implements OverriddenDefaultValue {
    async fn value<region r>(receiver read self: Self from r): i32 {
        self.value
    }
}

interface Sized2 {
    fn base<region r>(receiver read self: Self from r): i32
    async fn doubled<region r>(receiver read self: Self from r) {
        self.base() * 2
    }
}

type CapturedNumber { value: i32 }
extend CapturedNumber implements Sized2 {
    fn base<region r>(receiver read self: Self from r): i32 { self.value }
}

interface AsyncValue {
    async fn value<region r>(receiver read self: Self from r): i32
    async fn doubled<region r>(receiver read self: Self from r) {
        (await self.value()) * 2
    }
}

type AwaitedNumber { value: i32 }
extend AwaitedNumber implements AsyncValue {
    async fn value<region r>(receiver read self: Self from r): i32 {
        self.value
    }
}

fn drive<F: Future<Output = i32>>(take future: F): i32 {
    let waker = noop_waker()
    var slot = core.pin.pin(future)
    loop {
        var cx = Context.from_waker(read waker)
        match take slot.as_mut().poll(mut cx) {
            Poll.Ready(value) => { return value },
            Poll.Pending => {}
        }
    }
}

fn main(): i32 {
    if drive(ExplicitNumber(17).value()) != 17 { return 1 }
    if drive(InferredNumber().value()) != 42 { return 2 }
    if drive(OverriddenNumber(17).value()) != 17 { return 3 }
    if drive(CapturedNumber(21).doubled()) != 42 { return 4 }
    if drive(AwaitedNumber(21).doubled()) != 42 { return 5 }
    0
}
