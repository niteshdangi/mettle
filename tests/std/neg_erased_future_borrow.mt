// expect-error: region 16:18 borrowed source does not outlive the required region
import alloc.future
import core.future.{Context, Future, Poll}

type Borrowed<region r> { value: read i32 from r }
extend<region r> Borrowed<region r> implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        Poll.Ready(*me.value)
    }
}

fn main(): i32 {
    let value = 5
    let erased = future.erase(Borrowed(read value))
    0
}
