// expect-error-count: 2
// expect-error: region 21:13 viewed source does not outlive the required region
// expect-error: region 22:13 viewed source does not outlive the required region
import alloc.arc.Arc
import core.convert.From
import core.future.Waker
import std.task.{Wake, waker_from_arc}

type Borrowed<region r> { value: read i32 from r }
extend<region r> Borrowed<region r> implements Wake {
    fn wake(read me: Arc<Borrowed<region r>>): Unit {
        let _ = *self.value
    }
}
unsafe extend<region r> Borrowed<region r> implements Transferable {}
unsafe extend<region r> Borrowed<region r> implements Shareable {}

fn reject<region r>(read value: i32 from r): Unit {
    let first = alloc.arc.new(Borrowed(read value))
    let second = first.retain()
    let _ = waker_from_arc(read first)
    let _ = Waker.(From<Arc<Borrowed<region r>>>).from(second)
}

fn main(): i32 { 0 }
