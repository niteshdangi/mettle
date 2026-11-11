// expect-error: ownership 31:5 access or storage lifetime conflicts with a live read loan
import core.future.{Context, Future, Poll}
import std.thread.{Brand, Within}

type Child<region r> { value: read i32 from r }
extend<region r> Child<region r> implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        Poll.Ready(*me.value)
    }
}

// This models the invariant nominal region and mutable registration receiver
// needed by an async scope; the method must not use a shorter reborrow for s.
type Registry<region s> {
    anchor: read i32 from s
    brand: core.cell.Cell<Brand<region s>>
}
extend<region s> Registry<region s> {
    mut fn register<F: Future<Output = i32> + Within<region s>>(take future: F): Unit {}
    fn value(): i32 { *self.anchor }
}

fn main(): i32 {
    let anchor = 1
    var registry = Registry(read anchor, core.cell.Cell.new(Brand(0u8)))
    {
        let inner = 2
        registry.register(Child(read inner))
    }
    registry.value() - 1
}
