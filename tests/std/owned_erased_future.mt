import core.future.{Context, Future, Poll}

type Counted {
    drops: ptr<mut i32>
    polls: i32
    drop { unsafe { *self.drops = *self.drops + 1 } }
}

extend Counted implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        me.polls = me.polls + 1
        if me.polls < 3 {
            cx.waker().wake_by_ref()
            Poll.Pending
        } else {
            Poll.Ready(40 + me.polls - 1)
        }
    }
}

fn drive(owner: mut heap any Future<Output = i32>): i32 {
    let waker = core.future.noop_waker()
    loop {
        var cx = Context.from_waker(read waker)
        // The heap payload has a stable address and is not moved while polled.
        var handle = unsafe { core.pin.Pin.new_unchecked(owner.get_mut()) }
        match take handle.poll(mut cx) {
            Poll.Ready(value) => { return value },
            Poll.Pending => {}
        }
    }
}

fn main(): i32 {
    var drops = 0
    {
        var owner: heap any Future<Output = i32> = heap Counted(core.ptr.from_mut(drops), 0)
        if drive(mut owner) != 42 { return 1 }
        if drops != 0 { return 2 }
    }
    if drops != 1 { return 3 }
    {
        let _unpolled: heap any Future<Output = i32> = heap Counted(core.ptr.from_mut(drops), 0)
    }
    if drops != 2 { return 4 }
    0
}
